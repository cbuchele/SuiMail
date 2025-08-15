module suimail::profile_v2 {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use suimail::admin::AdminCap;

    const ENotAuthorized: u64 = 1;
    const EProfileAlreadyExists: u64 = 2;
    const EProfileNotFound: u64 = 3;
    const EInvalidUsername: u64 = 4;

    /// Registry to store all user profiles
    public struct ProfileRegistry has key {
        id: UID,
        profiles: Table<address, UserProfile>,
        username_to_address: Table<String, address>, // Reverse lookup for usernames
        owner: address,
    }

    /// Represents a user's profile for email system
    public struct UserProfile has key, store {
        id: UID,
        username: String,              // Human-readable username (e.g., "alice")
        display_name: String,          // Display name for emails
        bio: String,                   // User bio
        avatar_cid: vector<u8>,        // Avatar image CID in Walrus
        email_signature: String,       // Default email signature
        theme_preference: String,      // UI theme preference
        notification_settings: NotificationSettings,
        created_at: u64,
        last_active: u64,
        owner: address,
    }

    /// Notification settings for email
    public struct NotificationSettings has store {
        email_notifications: bool,     // Receive email notifications
        push_notifications: bool,      // Receive push notifications
        marketing_emails: bool,        // Receive marketing emails
        security_alerts: bool,         // Receive security alerts
    }

    /// Initialize the ProfileRegistry (called once during deployment)
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        transfer::share_object(ProfileRegistry {
            id: object::new(ctx),
            profiles: table::new(ctx),
            username_to_address: table::new(ctx),
            owner: deployer,
        });
    }

    /// Create a new user profile (limited to one per user)
    public entry fun register_profile(
        registry: &mut ProfileRegistry,
        username: String,
        display_name: String,
        bio: String,
        avatar_cid: vector<u8>,
        email_signature: String,
        theme_preference: String,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = tx_context::epoch(ctx);
        
        // Check if user already has a profile
        assert!(!table::contains(&registry.profiles, owner), EProfileAlreadyExists);
        
        // Check if username is already taken
        assert!(!table::contains(&registry.username_to_address, username), EInvalidUsername);
        
        // Validate username format (basic validation)
        assert!(string::length(&username) >= 3, EInvalidUsername);
        assert!(string::length(&username) <= 30, EInvalidUsername);

        let profile = UserProfile {
            id: object::new(ctx),
            username,
            display_name,
            bio,
            avatar_cid,
            email_signature,
            theme_preference,
            notification_settings: NotificationSettings {
                email_notifications: true,
                push_notifications: true,
                marketing_emails: false,
                security_alerts: true,
            },
            created_at: current_time,
            last_active: current_time,
            owner,
        };

        // Add profile to registry
        table::add(&mut registry.profiles, owner, profile);
        
        // Add username to reverse lookup
        table::add(&mut registry.username_to_address, username, owner);
    }

    /// Update the profile (user-specific function)
    public entry fun update_profile(
        registry: &mut ProfileRegistry,
        display_name: String,
        bio: String,
        avatar_cid: vector<u8>,
        email_signature: String,
        theme_preference: String,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound);

        let profile = table::borrow_mut(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized);

        profile.display_name = display_name;
        profile.bio = bio;
        profile.avatar_cid = avatar_cid;
        profile.email_signature = email_signature;
        profile.theme_preference = theme_preference;
        profile.last_active = tx_context::epoch(ctx);
    }

    /// Update notification settings
    public entry fun update_notification_settings(
        registry: &mut ProfileRegistry,
        email_notifications: bool,
        push_notifications: bool,
        marketing_emails: bool,
        security_alerts: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound);

        let profile = table::borrow_mut(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized);

        profile.notification_settings.email_notifications = email_notifications;
        profile.notification_settings.push_notifications = push_notifications;
        profile.notification_settings.marketing_emails = marketing_emails;
        profile.notification_settings.security_alerts = security_alerts;
        profile.last_active = tx_context::epoch(ctx);
    }

    /// Update username (requires admin approval to prevent conflicts)
    public entry fun update_username(
        registry: &mut ProfileRegistry,
        new_username: String,
        _admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound);
        
        // Validate new username
        assert!(string::length(&new_username) >= 3, EInvalidUsername);
        assert!(string::length(&new_username) <= 30, EInvalidUsername);
        assert!(!table::contains(&registry.username_to_address, new_username), EInvalidUsername);

        let profile = table::borrow_mut(&mut registry.profiles, caller);
        let old_username = profile.username;
        
        // Remove old username from reverse lookup
        table::remove(&mut registry.username_to_address, old_username);
        
        // Update username
        profile.username = new_username;
        profile.last_active = tx_context::epoch(ctx);
        
        // Add new username to reverse lookup
        table::add(&mut registry.username_to_address, new_username, caller);
    }

    /// Get profile by address
    public fun get_profile(registry: &ProfileRegistry, user: address): (String, String, String, vector<u8>, String) {
        if (table::contains(&registry.profiles, user)) {
            let profile = table::borrow(&registry.profiles, user);
            (profile.username, profile.display_name, profile.bio, profile.avatar_cid, profile.email_signature)
        } else {
            (string::utf8(b""), string::utf8(b""), string::utf8(b""), vector::empty<u8>(), string::utf8(b""))
        }
    }

    /// Get profile by username
    public fun get_profile_by_username(registry: &ProfileRegistry, username: String): (address, String, String, vector<u8>) {
        if (table::contains(&registry.username_to_address, username)) {
            let user_address = table::borrow(&registry.username_to_address, username);
            let profile = table::borrow(&registry.profiles, *user_address);
            (profile.owner, profile.display_name, profile.bio, profile.avatar_cid)
        } else {
            (0x0, string::utf8(b""), string::utf8(b""), vector::empty<u8>())
        }
    }

    /// Check if username is available
    public fun is_username_available(registry: &ProfileRegistry, username: String): bool {
        !table::contains(&registry.username_to_address, username)
    }

    /// Get user's notification settings
    public fun get_notification_settings(registry: &ProfileRegistry, user: address): (bool, bool, bool, bool) {
        if (table::contains(&registry.profiles, user)) {
            let profile = table::borrow(&registry.profiles, user);
            let settings = &profile.notification_settings;
            (settings.email_notifications, settings.push_notifications, settings.marketing_emails, settings.security_alerts)
        } else {
            (false, false, false, false)
        }
    }

    /// Update last active timestamp
    public entry fun update_last_active(
        registry: &mut ProfileRegistry,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        if (table::contains(&registry.profiles, caller)) {
            let profile = table::borrow_mut(&mut registry.profiles, caller);
            profile.last_active = tx_context::epoch(ctx);
        };
    }

    /// Reset a user profile (admin-only function)
    public entry fun reset_profile(
        registry: &mut ProfileRegistry,
        user: address,
        _admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, ENotAuthorized);
        assert!(table::contains(&registry.profiles, user), EProfileNotFound);

        let profile = table::borrow_mut(&mut registry.profiles, user);
        let old_username = profile.username;
        
        // Reset profile fields
        profile.display_name = string::utf8(b"");
        profile.bio = string::utf8(b"");
        profile.avatar_cid = vector::empty<u8>();
        profile.email_signature = string::utf8(b"");
        profile.theme_preference = string::utf8(b"light");
        profile.last_active = tx_context::epoch(ctx);
        
        // Reset notification settings
        profile.notification_settings.email_notifications = true;
        profile.notification_settings.push_notifications = true;
        profile.notification_settings.marketing_emails = false;
        profile.notification_settings.security_alerts = true;
        
        // Remove old username from reverse lookup
        table::remove(&mut registry.username_to_address, old_username);
        
        // Add reset username to reverse lookup
        let reset_username = string::utf8(b"user");
        profile.username = reset_username;
        table::add(&mut registry.username_to_address, reset_username, user);
    }

    /// Delete the profile (user-specific function)
    public entry fun delete_profile(
        registry: &mut ProfileRegistry,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound);

        let profile = table::remove(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized);

        // Remove username from reverse lookup
        table::remove(&mut registry.username_to_address, profile.username);

        let UserProfile { id, username: _, display_name: _, bio: _, avatar_cid: _, email_signature: _, theme_preference: _, notification_settings: _, created_at: _, last_active: _, owner: _ } = profile;
        object::delete(id);
    }

    /// Get profile statistics
    public fun get_profile_stats(registry: &ProfileRegistry): (u64, u64) {
        let total_profiles = 0;
        let active_profiles = 0;
        // Note: This would need to be implemented with counters
        // For now, returning placeholder values
        (total_profiles, active_profiles)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}