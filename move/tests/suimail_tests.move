#[test_only]
module suimail::suimail_tests {
    use sui::object::{UID};
    use sui::tx_context::{Self, TestingContext};
    use sui::transfer;
    use std::option;
    use suimail::profile::{Self, UserProfile};
    use suimail::kiosk::{Self, UserKiosk};
    use suimail::admin::{Self, AdminCap};

    /// Helper function to register a new profile
    fun register_test_profile(ctx: &mut TestingContext): UserProfile {
        suimail::profile::register_profile(
            b"test_user",
            b"Test Display Name",
            b"This is a bio",
            b"avatar_cid_placeholder",
            ctx
        )
    }

    /// Test registering a new profile
    #[test]
    fun test_register_profile() {
        let mut ctx = TestingContext::new();
        let profile = register_test_profile(&mut ctx);
        assert!(profile.username == b"test_user", 1);
        assert!(profile.display_name == b"Test Display Name", 2);
        assert!(profile.bio == b"This is a bio", 3);
    }

    /// Test updating an existing profile
    #[test]
    fun test_update_profile() {
        let mut ctx = TestingContext::new();
        let mut profile = register_test_profile(&mut ctx);
        
        suimail::profile::update_profile(
            &mut profile,
            b"Updated Display Name",
            b"Updated bio",
            b"updated_avatar_cid",
            &mut ctx
        );

        assert!(profile.display_name == b"Updated Display Name", 1);
        assert!(profile.bio == b"Updated bio", 2);
        assert!(profile.avatar_cid == b"updated_avatar_cid", 3);
    }

    /// Test linking a kiosk to a profile
    #[test]
    fun test_link_kiosk() {
        let mut ctx = TestingContext::new();
        let mut profile = register_test_profile(&mut ctx);

        // Initialize a kiosk
        suimail::kiosk::init_kiosk(&mut ctx);
        let kiosk = suimail::kiosk::create_test_kiosk(&mut ctx); // Assuming a helper function exists

        suimail::profile::link_kiosk(&mut profile, &kiosk, &mut ctx);
        assert!(option::is_some(&profile.kiosk_id), 1);
    }

    /// Test unlinking a kiosk from a profile
    #[test]
    fun test_unlink_kiosk() {
        let mut ctx = TestingContext::new();
        let mut profile = register_test_profile(&mut ctx);

        suimail::kiosk::init_kiosk(&mut ctx);
        let kiosk = suimail::kiosk::create_test_kiosk(&mut ctx);

        suimail::profile::link_kiosk(&mut profile, &kiosk, &mut ctx);
        suimail::profile::unlink_kiosk(&mut profile, &mut ctx);
        
        assert!(option::is_none(&profile.kiosk_id), 1);
    }

    /// Test resetting a profile (admin-only function)
    #[test]
    fun test_reset_profile() {
        let mut ctx = TestingContext::new();
        let mut profile = register_test_profile(&mut ctx);
        suimail::admin::init(&mut ctx); // Create admin cap
        let admin_cap = suimail::admin::create_test_admin_cap(&mut ctx); // Assuming a helper function exists

        suimail::profile::reset_profile(&mut profile, &admin_cap, &mut ctx);
        assert!(profile.display_name == b"", 1);
        assert!(profile.bio == b"", 2);
        assert!(option::is_none(&profile.kiosk_id), 3);
    }

    /// Test deleting a profile
    #[test]
    fun test_delete_profile() {
        let mut ctx = TestingContext::new();
        let profile = register_test_profile(&mut ctx);

        suimail::profile::delete_profile(profile, &mut ctx);
        assert!(!suimail::profile::exists(profile.owner), 1); // Ensure the profile no longer exists
    }
}
