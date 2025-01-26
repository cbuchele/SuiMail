module suimail::admin {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;

    /// Admin capability resource
    public struct AdminCap has key {
        id: UID,
    }

    /// Represents a bank object for collecting fees.
    public struct Bank has key {
        id: UID,           // Unique ID for the bank
        admin: address,    // Admin who can withdraw fees
        balance: Coin<u64>, // Collected fees
    }

    /// Initialize the admin capability and assign it to the deployer
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);

        // Initialize AdminCap
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, deployer);

        // Initialize Bank
        let bank = Bank {
            id: object::new(ctx),
            admin: deployer,
            balance: coin::zero<u64>(ctx), // Initialize with zero balance
        };
        transfer::transfer(bank, deployer);
    }

    /// ✅ Public function to deposit fees into the bank
    public fun deposit_fees(bank: &mut Bank, payment: Coin<u64>) {
        coin::join(&mut bank.balance, payment);
    }

    /// ✅ Public function for the admin to withdraw fees
    public entry fun withdraw_fees(
        bank: &mut Bank,
        admin_cap: &AdminCap, // Requires admin capability
        amount: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == bank.admin, 1); // Ensure only the admin can withdraw

        let withdrawn = coin::split(&mut bank.balance, amount, ctx);
        transfer::public_transfer(withdrawn, caller);
    }
}