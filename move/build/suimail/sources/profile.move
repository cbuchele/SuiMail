module suimail::profile {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use std::option::{Self, Option};
    use suimail::kiosk::UserKiosk;
    use suimail::admin::AdminCap;

    const ENotAuthorized: u64 = 1;
    const EKioskAlreadyLinked: u64 = 2;
    const EProfileAlreadyExists: u64 = 3;
    const EProfileNotFound: u64 = 4;

    /// Registry to store all user profiles
    public struct ProfileRegistry has key {
        id: UID,
        profiles: Table<address, UserProfile>, // Maps owner address to their profile
        owner: address, // Admin/owner of the registry (deployer)
    }

    /// Represents a user's profile with customizable fields
    public struct UserProfile has key, store {
        id: UID,
        username: vector<u8>,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        owner: address,
        kiosk_id: Option<ID>, // Linked kiosk ID
    }

    /// Initialize the ProfileRegistry (called once during deployment)
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        transfer::share_object(ProfileRegistry {
            id: object::new(ctx),
            profiles: table::new(ctx),
            owner: deployer,
        });
    }

    /// Create a new user profile (user-specific function)
    public entry fun register_profile(
        registry: &mut ProfileRegistry,
        username: vector<u8>,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        assert!(!table::contains(&registry.profiles, owner), EProfileAlreadyExists); // Ensure no profile exists

        let profile = UserProfile {
            id: object::new(ctx),
            username,
            display_name,
            bio,
            avatar_cid,
            owner,
            kiosk_id: option::none(),
        };

        table::add(&mut registry.profiles, owner, profile); // Store in registry
    }

    /// Update the profile (user-specific function)
    public entry fun update_profile(
        registry: &mut ProfileRegistry,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound); // Ensure profile exists

        let profile = table::borrow_mut(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner

        profile.display_name = display_name;
        profile.bio = bio;
        profile.avatar_cid = avatar_cid;
    }

    /// Link a kiosk to the profile (user-specific function)
    public entry fun link_kiosk(
        registry: &mut ProfileRegistry,
        kiosk: &UserKiosk,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound); // Ensure profile exists

        let profile = table::borrow_mut(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner
        assert!(option::is_none(&profile.kiosk_id), EKioskAlreadyLinked); // Ensure no kiosk is linked yet

        let kiosk_owner = suimail::kiosk::get_owner(kiosk);
        assert!(caller == kiosk_owner, ENotAuthorized); // Verify kiosk ownership

        let kiosk_id = object::id(kiosk);
        profile.kiosk_id = option::some(kiosk_id);
    }

    /// Reset a user profile (admin-only function)
    public entry fun reset_profile(
        registry: &mut ProfileRegistry,
        user: address,
        _admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        let admin = tx_context::sender(ctx);
        assert!(admin == registry.owner, ENotAuthorized); // Ensure caller is the registry owner
        assert!(table::contains(&registry.profiles, user), EProfileNotFound); // Ensure profile exists

        let profile = table::borrow_mut(&mut registry.profiles, user);
        profile.display_name = vector::empty();
        profile.bio = vector::empty();
        profile.avatar_cid = vector::empty();
        profile.kiosk_id = option::none();
    }

    /// Delete the profile (user-specific function)
    public entry fun delete_profile(
        registry: &mut ProfileRegistry,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.profiles, caller), EProfileNotFound); // Ensure profile exists

        let profile = table::remove(&mut registry.profiles, caller);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner

        let UserProfile { id, username: _, display_name: _, bio: _, avatar_cid: _, owner: _, kiosk_id: _ } = profile;
        object::delete(id); // Delete the profile UID
    }
}