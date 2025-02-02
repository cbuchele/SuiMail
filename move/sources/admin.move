module suimail::admin {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    use std::vector;
    use sui::sui::SUI;

    /// Error Codes
    const E_NOT_ADMIN: u64 = 1;
    const E_NO_FUNDS: u64 = 2;

    /// **Admin capability (Only one should exist)**
    public struct AdminCap has key {
        id: UID,
        admin: address, // ✅ Fix: Added admin address field
    }

    public struct UserBankRegistry has key, store {
        id: UID,
        banks: Table<ID, UserBank>, // Use Table to store UserBank objects
        keys: vector<ID>, // Store keys of all UserBank objects
    }

    /// **User's Bank Account for Collecting Fees**
    public struct UserBank has key, store {
        id: UID,            // Unique ID for the user's bank
        owner: address,     // Owner of the bank (cannot withdraw)
        balance: Coin<SUI>, // Accumulated fees (stored in SUI)
    }

    /// ✅ **Initialize the Admin and System**
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);

        // ✅ Create Admin Capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: deployer,
        };
        transfer::transfer(admin_cap, deployer);

        // Create User Bank Registry with an empty Table and keys vector
        let registry = UserBankRegistry {
            id: object::new(ctx),
            banks: table::new<ID, UserBank>(ctx),
            keys: vector::empty<ID>(),
        };
        transfer::share_object(registry);
    }

    /// CREATE USER BANK
    public entry fun create_user_bank(
        registry: &mut UserBankRegistry,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let bank = UserBank {
            id: object::new(ctx),
            owner,
            balance: coin::zero<SUI>(ctx),
        };

        let bank_id = object::id(&bank);
        table::add(&mut registry.banks, bank_id, bank); // Add UserBank to the Table
        vector::push_back(&mut registry.keys, bank_id); // Add the key to the keys vector
    }

    /// ✅ **Users Can Deposit Fees (Cannot Withdraw)**
    public entry fun deposit_fees(user_bank: &mut UserBank, payment: Coin<SUI>) {
        coin::join(&mut user_bank.balance, payment); // ✅ Merge fees into balance
    }

    public entry fun collect_fees(
    admin_cap: &AdminCap,
    registry: &mut UserBankRegistry,
    ctx: &mut TxContext
) {
    let caller = tx_context::sender(ctx);
    assert!(caller == admin_cap.admin, E_NOT_ADMIN);

    let mut total_collected = coin::zero<SUI>(ctx);
    let bank_ids = &registry.keys; // Get all UserBank IDs from the keys vector

    let mut i = 0;
    while (i < vector::length(bank_ids)) {
        let bank_id = vector::borrow(bank_ids, i);
        let bank = table::borrow_mut(&mut registry.banks, *bank_id); // Borrow mutable reference

        let bank_balance = coin::value(&bank.balance);
        if (bank_balance > 0) {
            let collected = coin::split(&mut bank.balance, bank_balance, ctx);
            coin::join(&mut total_collected, collected);
        }; // Semicolon required after if block

        i = i + 1; // Increment the loop counter
    }; // Semicolon required after while loop

    assert!(coin::value(&total_collected) > 0, E_NO_FUNDS);
    transfer::public_transfer(total_collected, caller);
}

    /// ✅ **Admin Can Collect Fees from a Single `UserBank`**
    public entry fun collect_fees_single(
        admin_cap: &AdminCap,
        user_bank: &mut UserBank,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(caller == admin_cap.admin, E_NOT_ADMIN); // ✅ Fix assertion

        let bank_balance = coin::value(&user_bank.balance);
        assert!(bank_balance > 0, E_NO_FUNDS); // ✅ Ensure bank has funds

        let collected = coin::split(&mut user_bank.balance, bank_balance, ctx);
        transfer::public_transfer(collected, caller);
    }
}