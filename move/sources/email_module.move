module suimail::profile {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::option::{Self, Option};
    use suimail::kiosk::UserKiosk;
    use suimail::admin::AdminCap;

    const ENotAuthorized: u64 = 1;

    /// Represents a user's profile with customizable fields.
    public struct UserProfile has store, key {
        id: UID,
        username: vector<u8>,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        owner: address,
        kiosk_id: option::Option<address>, // Linked kiosk
    }

    /// Create a new user profile (user-specific function).
    public entry fun register_profile(
        username: vector<u8>,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx); // Get sender's address
        let id = object::new(ctx); // Create new UID
        let profile = UserProfile {
            id,
            username,
            display_name,
            bio,
            avatar_cid,
            owner,
            kiosk_id: option::none()
        };
        transfer::transfer(profile, owner); // Transfer ownership
    }

    /// Update the profile (user-specific function).
    public entry fun update_profile(
        profile: &mut UserProfile,
        display_name: vector<u8>,
        bio: vector<u8>,
        avatar_cid: vector<u8>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner
        profile.display_name = display_name;
        profile.bio = bio;
        profile.avatar_cid = avatar_cid;
    }

    /// Link a kiosk to the profile (user-specific function).
    public entry fun link_kiosk(
        profile: &mut UserProfile,
        kiosk: &UserKiosk,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner
        assert!(option::is_none(&profile.kiosk_id), 2);   // Ensure no kiosk is linked yet

        let kiosk_owner = suimail::kiosk::get_owner(kiosk); // Use the getter function
        profile.kiosk_id = option::some(kiosk_owner);
    }

    /// Reset a user profile (admin-only function).
    public entry fun reset_profile(
        profile: &mut UserProfile,
        admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        // Ensure admin capability is provided by the caller
        let _admin_owner = tx_context::sender(ctx);
        profile.display_name = vector::empty();
        profile.bio = vector::empty();
        profile.avatar_cid = vector::empty();
        profile.kiosk_id = option::none();
    }

    /// Delete the profile (user-specific function).
    public entry fun delete_profile(
        profile: UserProfile,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == profile.owner, ENotAuthorized); // Ensure caller is the owner

        let UserProfile { id, username: _, display_name: _, bio: _, avatar_cid: _, owner: _, kiosk_id: _ } = profile;
        object::delete(id); // Delete the profile by its UID
    }
}