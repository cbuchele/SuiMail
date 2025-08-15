module suimail::walrus_integration {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;
    use sui::clock::{Self, Clock};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_CONTENT_NOT_FOUND: u64 = 2;
    const E_INVALID_CONTENT_SIZE: u64 = 3;
    const E_CONTENT_EXPIRED: u64 = 4;
    const E_INSUFFICIENT_STORAGE: u64 = 5;

    /// Walrus storage configuration
    const MAX_CONTENT_SIZE: u64 = 50_000_000; // 50MB max per content piece
    const DEFAULT_RETENTION_DAYS: u64 = 365; // 1 year default retention
    const MAX_RETENTION_DAYS: u64 = 2555; // 7 years max retention

    /// Content metadata stored on-chain
    public struct WalrusContent has key, store {
        id: UID,
        content_id: vector<u8>,        // Walrus CID
        content_hash: vector<u8>,      // SHA256 hash for verification
        content_type: String,          // MIME type
        size_bytes: u64,
        owner: address,
        created_at: u64,
        expires_at: u64,
        retention_days: u64,
        encryption_key: vector<u8>,    // Encrypted encryption key
        tags: vector<String>,          // For categorization
        is_public: bool,               // Whether content is publicly accessible
    }

    /// Storage allocation for users
    public struct StorageAllocation has key, store {
        id: UID,
        owner: address,
        total_allocated: u64,          // Total storage allocated in bytes
        used_storage: u64,             // Currently used storage in bytes
        max_file_size: u64,            // Maximum file size allowed
        retention_days: u64,           // Default retention period
        created_at: u64,
        last_updated: u64,
    }

    /// Walrus storage registry
    public struct WalrusRegistry has key {
        id: UID,
        owner: address,
        content_store: Table<vector<u8>, WalrusContent>,
        user_allocations: Table<address, StorageAllocation>,
        total_storage_allocated: u64,
        total_storage_used: u64,
        storage_fee_per_gb: u64,       // Storage fee per GB per month
        max_total_storage_gb: u64,     // Maximum total storage across all users
    }

    /// Events
    public struct ContentStored has copy, drop {
        content_id: vector<u8>,
        owner: address,
        size_bytes: u64,
        content_type: String,
        timestamp: u64,
    }

    public struct ContentDeleted has copy, drop {
        content_id: vector<u8>,
        owner: address,
        timestamp: u64,
    }

    public struct StorageAllocated has copy, drop {
        owner: address,
        allocated_bytes: u64,
        timestamp: u64,
    }

    /// Initialize the Walrus integration module
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        transfer::share_object(WalrusRegistry {
            id: object::new(ctx),
            owner: deployer,
            content_store: table::new(ctx),
            user_allocations: table::new(ctx),
            total_storage_allocated: 0,
            total_storage_used: 0,
            storage_fee_per_gb: 1_000_000_000, // 1 SUI per GB per month
            max_total_storage_gb: 1000, // 1TB max total storage
        });
    }

    /// Allocate storage for a user
    public entry fun allocate_storage(
        registry: &mut WalrusRegistry,
        allocated_bytes: u64,
        max_file_size: u64,
        retention_days: u64,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Validate allocation size
        assert!(allocated_bytes > 0, E_INVALID_CONTENT_SIZE);
        assert!(max_file_size <= MAX_CONTENT_SIZE, E_INVALID_CONTENT_SIZE);
        assert!(retention_days <= MAX_RETENTION_DAYS, E_INVALID_CONTENT_SIZE);
        
        // Check if user already has allocation
        if (table::contains(&registry.user_allocations, owner)) {
            let allocation = table::borrow_mut(&mut registry.user_allocations, owner);
            allocation.total_allocated = allocation.total_allocated + allocated_bytes;
            allocation.max_file_size = max_file_size;
            allocation.retention_days = retention_days;
            allocation.last_updated = current_time;
        } else {
            let allocation = StorageAllocation {
                id: object::new(ctx),
                owner,
                total_allocated: allocated_bytes,
                used_storage: 0,
                max_file_size,
                retention_days,
                created_at: current_time,
                last_updated: current_time,
            };
            table::add(&mut registry.user_allocations, owner, allocation);
        };

        registry.total_storage_allocated = registry.total_storage_allocated + allocated_bytes;

        event::emit(StorageAllocated {
            owner,
            allocated_bytes,
            timestamp: current_time,
        });
    }

    /// Store content metadata on-chain
    public entry fun store_content(
        registry: &mut WalrusRegistry,
        content_id: vector<u8>,
        content_hash: vector<u8>,
        content_type: String,
        size_bytes: u64,
        encryption_key: vector<u8>,
        tags: vector<String>,
        is_public: bool,
        retention_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate content size
        assert!(size_bytes > 0, E_INVALID_CONTENT_SIZE);
        assert!(size_bytes <= MAX_CONTENT_SIZE, E_INVALID_CONTENT_SIZE);
        
        // Check if user has storage allocation
        assert!(table::contains(&registry.user_allocations, owner), E_INSUFFICIENT_STORAGE);
        let allocation = table::borrow_mut(&registry.user_allocations, owner);
        
        // Check if user has enough storage
        assert!(allocation.used_storage + size_bytes <= allocation.total_allocated, E_INSUFFICIENT_STORAGE);
        
        // Use user's default retention if not specified
        let final_retention = if (retention_days == 0) { allocation.retention_days } else { retention_days };
        let expires_at = current_time + (final_retention * 86400000); // Convert days to milliseconds
        
        let content = WalrusContent {
            id: object::new(ctx),
            content_id,
            content_hash,
            content_type,
            size_bytes,
            owner,
            created_at: current_time,
            expires_at,
            retention_days: final_retention,
            encryption_key,
            tags,
            is_public,
        };

        table::add(&mut registry.content_store, content_id, content);
        
        // Update user's used storage
        allocation.used_storage = allocation.used_storage + size_bytes;
        allocation.last_updated = current_time;
        
        // Update registry totals
        registry.total_storage_used = registry.total_storage_used + size_bytes;

        event::emit(ContentStored {
            content_id,
            owner,
            size_bytes,
            content_type,
            timestamp: current_time,
        });
    }

    /// Delete content and free up storage
    public entry fun delete_content(
        registry: &mut WalrusRegistry,
        content_id: vector<u8>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Check if content exists
        assert!(table::contains(&registry.content_store, content_id), E_CONTENT_NOT_FOUND);
        let content = table::borrow(&registry.content_store, content_id);
        
        // Check if caller owns the content
        assert!(caller == content.owner, E_NOT_AUTHORIZED);
        
        let size_bytes = content.size_bytes;
        let owner = content.owner;
        
        // Remove content from store
        let _content = table::remove(&mut registry.content_store, content_id);
        object::delete(_content.id);
        
        // Update user's used storage
        if (table::contains(&registry.user_allocations, owner)) {
            let allocation = table::borrow_mut(&mut registry.user_allocations, owner);
            allocation.used_storage = allocation.used_storage - size_bytes;
            allocation.last_updated = tx_context::epoch(ctx);
        };
        
        // Update registry totals
        registry.total_storage_used = registry.total_storage_used - size_bytes;

        event::emit(ContentDeleted {
            content_id,
            owner,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Update content metadata
    public entry fun update_content(
        registry: &mut WalrusRegistry,
        content_id: vector<u8>,
        new_tags: vector<String>,
        new_is_public: bool,
        new_retention_days: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Check if content exists
        assert!(table::contains(&registry.content_store, content_id), E_CONTENT_NOT_FOUND);
        let content = table::borrow_mut(&mut registry.content_store, content_id);
        
        // Check if caller owns the content
        assert!(caller == content.owner, E_NOT_AUTHORIZED);
        
        // Validate retention days
        if (new_retention_days > 0) {
            assert!(new_retention_days <= MAX_RETENTION_DAYS, E_INVALID_CONTENT_SIZE);
            content.retention_days = new_retention_days;
            content.expires_at = tx_context::epoch(ctx) + (new_retention_days * 86400000);
        };
        
        content.tags = new_tags;
        content.is_public = new_is_public;
    }

    /// Get content metadata
    public fun get_content(registry: &WalrusRegistry, content_id: vector<u8>): (address, String, u64, u64, bool) {
        if (table::contains(&registry.content_store, content_id)) {
            let content = table::borrow(&registry.content_store, content_id);
            (content.owner, content.content_type, content.size_bytes, content.expires_at, content.is_public)
        } else {
            (0x0, string::utf8(b""), 0, 0, false)
        }
    }

    /// Get user's storage allocation
    public fun get_user_storage(registry: &WalrusRegistry, user: address): (u64, u64, u64) {
        if (table::contains(&registry.user_allocations, user)) {
            let allocation = table::borrow(&registry.user_allocations, user);
            (allocation.total_allocated, allocation.used_storage, allocation.max_file_size)
        } else {
            (0, 0, 0)
        }
    }

    /// Check if content is accessible to user
    public fun is_content_accessible(registry: &WalrusRegistry, content_id: vector<u8>, user: address): bool {
        if (table::contains(&registry.content_store, content_id)) {
            let content = table::borrow(&registry.content_store, content_id);
            content.is_public || content.owner == user
        } else {
            false
        }
    }

    /// Get content tags
    public fun get_content_tags(registry: &WalrusRegistry, content_id: vector<u8>): vector<String> {
        if (table::contains(&registry.content_store, content_id)) {
            let content = table::borrow(&registry.content_store, content_id);
            content.tags
        } else {
            vector::empty<String>()
        }
    }

    /// Search content by tags
    public fun search_content_by_tags(registry: &WalrusRegistry, search_tags: vector<String>): vector<vector<u8>> {
        let matching_content = vector::empty<vector<u8>>();
        // Note: This would need to be implemented with an index
        // For now, returning empty vector
        matching_content
    }

    /// Clean up expired content
    public entry fun cleanup_expired_content(
        registry: &mut WalrusRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        
        // Note: This would iterate through all content and remove expired ones
        // Implementation would depend on specific requirements
    }

    /// Update storage fees (admin only)
    public entry fun set_storage_fee(
        registry: &mut WalrusRegistry,
        new_fee_per_gb: u64,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        registry.storage_fee_per_gb = new_fee_per_gb;
    }

    /// Update max total storage (admin only)
    public entry fun set_max_total_storage(
        registry: &mut WalrusRegistry,
        new_max_gb: u64,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, E_NOT_AUTHORIZED);
        registry.max_total_storage_gb = new_max_gb;
    }

    /// Get registry statistics
    public fun get_registry_stats(registry: &WalrusRegistry): (u64, u64, u64, u64) {
        (
            registry.total_storage_allocated,
            registry.total_storage_used,
            registry.storage_fee_per_gb,
            registry.max_total_storage_gb
        )
    }

    /// Calculate storage cost for a given size
    public fun calculate_storage_cost(registry: &WalrusRegistry, size_bytes: u64): u64 {
        let size_gb = size_bytes / 1_000_000_000; // Convert bytes to GB
        size_gb * registry.storage_fee_per_gb
    }
}