module suimail::suins_integration {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;
    use std::string::{Self, String};
    use std::vector;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_DOMAIN_EXISTS: u64 = 2;
    const E_DOMAIN_NOT_FOUND: u64 = 3;
    const E_INVALID_DOMAIN_FORMAT: u64 = 4;
    const E_DOMAIN_ALREADY_VERIFIED: u64 = 5;

    /// SuiNS domain record
    public struct SuiNSDomain has key, store {
        id: UID,
        domain_name: String,           // e.g., "user.sui"
        owner: address,
        email_enabled: bool,
        verified: bool,
        created_at: u64,
        last_updated: u64,
    }

    /// Domain verification request
    public struct DomainVerification has key, store {
        id: UID,
        domain_name: String,
        owner: address,
        verification_code: String,
        requested_at: u64,
        expires_at: u64,
    }

    /// SuiNS registry for managing domains
    public struct SuiNSRegistry has key {
        id: UID,
        owner: address,
        domains: Table<String, SuiNSDomain>,
        verification_requests: Table<String, DomainVerification>,
        supported_tlds: vector<String>, // Supported top-level domains
    }

    /// Events
    public struct DomainRegistered has copy, drop {
        domain_name: String,
        owner: address,
        timestamp: u64,
    }

    public struct DomainVerified has copy, drop {
        domain_name: String,
        owner: address,
        timestamp: u64,
    }

    public struct EmailEnabled has copy, drop {
        domain_name: String,
        owner: address,
        timestamp: u64,
    }

    /// Initialize the SuiNS integration module
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        
        // Initialize supported TLDs
        let supported_tlds = vector::empty<String>();
        let sui_tld = string::utf8(b"sui");
        let test_tld = string::utf8(b"test");
        
        vector::push_back(&mut supported_tlds, sui_tld);
        vector::push_back(&mut supported_tlds, test_tld);

        transfer::share_object(SuiNSRegistry {
            id: object::new(ctx),
            owner: deployer,
            domains: table::new(ctx),
            verification_requests: table::new(ctx),
            supported_tlds,
        });
    }

    /// Register a new SuiNS domain
    public entry fun register_domain(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Validate domain format
        assert!(is_valid_domain_format(&domain_name), E_INVALID_DOMAIN_FORMAT);
        
        // Check if domain already exists
        assert!(!table::contains(&registry.domains, domain_name), E_DOMAIN_EXISTS);
        
        // Check if TLD is supported
        assert!(is_supported_tld(&domain_name, &registry.supported_tlds), E_INVALID_DOMAIN_FORMAT);

        let domain = SuiNSDomain {
            id: object::new(ctx),
            domain_name,
            owner,
            email_enabled: false,
            verified: false,
            created_at: current_time,
            last_updated: current_time,
        };

        table::add(&mut registry.domains, domain.domain_name, domain);

        event::emit(DomainRegistered {
            domain_name: domain.domain_name,
            owner,
            timestamp: current_time,
        });
    }

    /// Request domain verification
    public entry fun request_verification(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        verification_code: String,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Check if domain exists and is owned by caller
        assert!(table::contains(&registry.domains, domain_name), E_DOMAIN_NOT_FOUND);
        let domain = table::borrow(&registry.domains, domain_name);
        assert!(domain.owner == owner, E_NOT_AUTHORIZED);
        assert!(!domain.verified, E_DOMAIN_ALREADY_VERIFIED);

        // Create verification request
        let verification = DomainVerification {
            id: object::new(ctx),
            domain_name,
            owner,
            verification_code,
            requested_at: current_time,
            expires_at: current_time + 86400, // 24 hours
        };

        table::add(&mut registry.verification_requests, domain_name, verification);
    }

    /// Complete domain verification (admin only)
    public entry fun verify_domain(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        verification_code: String,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        
        // Check if verification request exists
        assert!(table::contains(&registry.verification_requests, domain_name), E_DOMAIN_NOT_FOUND);
        let verification = table::borrow(&registry.verification_requests, domain_name);
        
        // Verify the code matches
        assert!(verification.verification_code == verification_code, E_INVALID_DOMAIN_FORMAT);
        
        // Check if verification hasn't expired
        let current_time = tx_context::epoch(ctx);
        assert!(current_time <= verification.expires_at, E_INVALID_DOMAIN_FORMAT);

        // Mark domain as verified
        let domain = table::borrow_mut(&mut registry.domains, domain_name);
        domain.verified = true;
        domain.last_updated = current_time;

        // Remove verification request
        let _verification = table::remove(&mut registry.verification_requests, domain_name);
        object::delete(_verification.id);

        event::emit(DomainVerified {
            domain_name,
            owner: domain.owner,
            timestamp: current_time,
        });
    }

    /// Enable email for a domain
    public entry fun enable_email(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Check if domain exists and is owned by caller
        assert!(table::contains(&registry.domains, domain_name), E_DOMAIN_NOT_FOUND);
        let domain = table::borrow_mut(&mut registry.domains, domain_name);
        assert!(domain.owner == owner, E_NOT_AUTHORIZED);
        assert!(domain.verified, E_DOMAIN_NOT_FOUND); // Must be verified first

        domain.email_enabled = true;
        domain.last_updated = current_time;

        event::emit(EmailEnabled {
            domain_name,
            owner,
            timestamp: current_time,
        });
    }

    /// Disable email for a domain
    public entry fun disable_email(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Check if domain exists and is owned by caller
        assert!(table::contains(&registry.domains, domain_name), E_DOMAIN_NOT_FOUND);
        let domain = table::borrow_mut(&mut registry.domains, domain_name);
        assert!(domain.owner == owner, E_NOT_AUTHORIZED);

        domain.email_enabled = false;
        domain.last_updated = current_time;
    }

    /// Transfer domain ownership
    public entry fun transfer_domain(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        let current_owner = tx_context::sender(ctx);
        
        // Check if domain exists and is owned by caller
        assert!(table::contains(&registry.domains, domain_name), E_DOMAIN_NOT_FOUND);
        let domain = table::borrow_mut(&mut registry.domains, domain_name);
        assert!(domain.owner == current_owner, E_NOT_AUTHORIZED);

        domain.owner = new_owner;
        domain.last_updated = tx_context::epoch(ctx);
    }

    /// Update domain settings
    public entry fun update_domain(
        registry: &mut SuiNSRegistry,
        domain_name: String,
        email_enabled: bool,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Check if domain exists and is owned by caller
        assert!(table::contains(&registry.domains, domain_name), E_DOMAIN_NOT_FOUND);
        let domain = table::borrow_mut(&mut registry.domains, domain_name);
        assert!(domain.owner == owner, E_NOT_AUTHORIZED);

        domain.email_enabled = email_enabled;
        domain.last_updated = current_time;
    }

    /// Get domain information
    public fun get_domain(registry: &SuiNSRegistry, domain_name: String): (address, bool, bool, u64) {
        if (table::contains(&registry.domains, domain_name)) {
            let domain = table::borrow(&registry.domains, domain_name);
            (domain.owner, domain.email_enabled, domain.verified, domain.created_at)
        } else {
            (0x0, false, false, 0)
        }
    }

    /// Check if domain is available for registration
    public fun is_domain_available(registry: &SuiNSRegistry, domain_name: String): bool {
        !table::contains(&registry.domains, domain_name)
    }

    /// Check if domain is valid for email use
    public fun is_domain_email_enabled(registry: &SuiNSRegistry, domain_name: String): bool {
        if (table::contains(&registry.domains, domain_name)) {
            let domain = table::borrow(&registry.domains, domain_name);
            domain.email_enabled && domain.verified
        } else {
            false
        }
    }

    /// Get all domains owned by an address
    public fun get_user_domains(registry: &SuiNSRegistry, user: address): vector<String> {
        let user_domains = vector::empty<String>();
        // Note: This would need to be implemented with a reverse lookup table
        // For now, returning empty vector
        user_domains
    }

    /// Helper function to validate domain format
    fun is_valid_domain_format(domain_name: &String): bool {
        let domain_str = string::bytes(domain_name);
        let length = vector::length(&domain_str);
        
        // Basic validation: must have at least 3 characters and contain a dot
        if (length < 3) return false;
        
        let mut has_dot = false;
        let mut i = 0;
        while (i < length) {
            let char = *vector::borrow(&domain_str, i);
            if (char == 46) { // ASCII for '.'
                has_dot = true;
            };
            i = i + 1;
        };
        
        has_dot
    }

    /// Helper function to check if TLD is supported
    fun is_supported_tld(domain_name: &String, supported_tlds: &vector<String>): bool {
        let domain_str = string::bytes(domain_name);
        let length = vector::length(&domain_str);
        
        // Find the last dot to get TLD
        let mut last_dot_index = 0;
        let mut i = 0;
        while (i < length) {
            let char = *vector::borrow(&domain_str, i);
            if (char == 46) { // ASCII for '.'
                last_dot_index = i;
            };
            i = i + 1;
        };
        
        // Extract TLD
        let tld_start = last_dot_index + 1;
        if (tld_start >= length) return false;
        
        let mut tld_bytes = vector::empty<u8>();
        let mut j = tld_start;
        while (j < length) {
            vector::push_back(&mut tld_bytes, *vector::borrow(&domain_str, j));
            j = j + 1;
        };
        
        let tld = string::utf8(tld_bytes);
        
        // Check if TLD is supported
        let mut k = 0;
        while (k < vector::length(supported_tlds)) {
            let supported_tld = vector::borrow(supported_tlds, k);
            if (string::bytes(&tld) == string::bytes(supported_tld)) {
                return true;
            };
            k = k + 1;
        };
        
        false
    }

    /// Add supported TLD (admin only)
    public entry fun add_supported_tld(
        registry: &mut SuiNSRegistry,
        tld: String,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        
        vector::push_back(&mut registry.supported_tlds, tld);
    }

    /// Remove supported TLD (admin only)
    public entry fun remove_supported_tld(
        registry: &mut SuiNSRegistry,
        tld: String,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        
        let mut i = 0;
        while (i < vector::length(&registry.supported_tlds)) {
            let current_tld = vector::borrow(&registry.supported_tlds, i);
            if (string::bytes(current_tld) == string::bytes(&tld)) {
                vector::remove(&mut registry.supported_tlds, i);
                return;
            };
            i = i + 1;
        };
    }
}