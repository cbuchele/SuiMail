module suimail::admin {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    /// Error Codes
    const E_NOT_ADMIN: u64 = 1;

    /// **Admin capability (Only one should exist)**
    public struct AdminCap has key {
        id: UID,
        admin: address, // Admin address
    }

    /// ✅ **Initialize the Admin Capability**
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);

        // Create Admin Capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: deployer,
        };
        transfer::transfer(admin_cap, deployer);
    }
}