module suimail::kiosk {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::vector;
    use sui::sui::SUI;

    use std::option::{Self, Option};
    use suimail::admin::{Self, UserBank}; // ✅ Import the Bank object

    /// Error codes
    const EItemNotFound: u64 = 1;
    const EIncorrectPayment: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EMaxItemsReached: u64 = 4;
    const E_INSUFFICIENT_FUNDS: u64 = 5; // New error for fee validation

    /// Registry to track all kiosks on-chain.
    public struct KioskRegistry has key, store {
        id: UID,                // UID for the registry
        kiosks: vector<ID>,     // List of kiosk IDs
        owners: vector<address>, // List of kiosk owners (parallel to kiosks)
    }

    /// Represents a single item in the kiosk.
    public struct KioskItem has store, drop {
        id: u64,
        title: vector<u8>,
        content_cid: vector<u8>,
        price: u64,      // Price of the item in SUI
        timestamp: u64,  // Timestamp of when the item was listed
    }

    /// Represents a user's kiosk with items for sale and accumulated balance.
    public struct UserKiosk has store, key {
        id: UID,
        owner: address,
        items: vector<KioskItem>, // List of items for sale
        balance: Coin<u64>,       // Accumulated balance from sales in SUI
    }

    /// ✅ Automatically initialize the kiosk registry when the module is published.
    fun init(ctx: &mut TxContext) {
        let registry = KioskRegistry {
            id: object::new(ctx),
            kiosks: vector::empty<ID>(),
            owners: vector::empty<address>(),
        };
        transfer::share_object(registry);  // Share the registry object
    }

    /// Get the owner of the kiosk.
    public fun get_owner(kiosk: &UserKiosk): address {
        kiosk.owner
    }

    /// Check if the given account is the owner of the kiosk.
    public fun is_owner(kiosk: &UserKiosk, caller: address): bool {
        caller == kiosk.owner
    }

    /// Check if the kiosk has an item with the given ID.
    public fun has_item(kiosk: &UserKiosk, item_id: u64): bool {
        let mut i = 0;
        while (i < vector::length(&kiosk.items)) {
            if (vector::borrow(&kiosk.items, i).id == item_id) {
                return true;
            };
            i = i + 1;
        };
        return false
    }

    /// ✅ Convert an `ID` to `u64` safely
    fun id_to_numeric(id: &ID): u64 {
        let bytes = object::id_to_bytes(id);
        (bytes[0] as u64) | ((bytes[1] as u64) << 8) | ((bytes[2] as u64) << 16) | ((bytes[3] as u64) << 24) |
        ((bytes[4] as u64) << 32) | ((bytes[5] as u64) << 40) | ((bytes[6] as u64) << 48) | ((bytes[7] as u64) << 56)
    }

    /// ✅ Initialize a new kiosk and register it
    public entry fun init_kiosk(
        user_bank: &mut suimail::admin::UserBank,
        mut payment: Coin<SUI>,
        registry: &mut KioskRegistry,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let balance = coin::zero(ctx);

        // Ensure the user has at least 10 SUI
        let required_payment = 10_000_000_000;
        let actual_payment = coin::value(&payment);

        assert!(actual_payment >= required_payment, E_INSUFFICIENT_FUNDS);

        // Extract 10 SUI from the payment coin
        let used_payment = coin::split(&mut payment, required_payment, ctx);
        suimail::admin::deposit_fees(user_bank, used_payment);

        // Refund remaining balance if any
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, sender);
        } else {
            coin::destroy_zero(payment); // Consume the remaining empty coin
        };

        // Initialize the Kiosk Object
        let kiosk = UserKiosk {
            id: object::new(ctx),
            owner: sender,
            items: vector::empty<KioskItem>(),
            balance,
        };

        let kiosk_id = object::id(&kiosk);
        vector::push_back(&mut registry.kiosks, kiosk_id);
        vector::push_back(&mut registry.owners, sender); // Add the owner's address

        // Use `public_share_object` to make the Kiosk public
        transfer::public_share_object(kiosk);
    }

    public fun get_kiosk_owner(registry: &KioskRegistry, kiosk_id: ID): address {
        let mut i = 0;
        while (i < vector::length(&registry.kiosks)) {
            if (vector::borrow(&registry.kiosks, i) == kiosk_id) {
                return *vector::borrow(&registry.owners, i);
            };
            i = i + 1;
        };
        abort EItemNotFound // Kiosk not found
    }

    /// Publish a new item to the kiosk.
    public entry fun publish_item(
        kiosk: &mut UserKiosk,
        title: vector<u8>,
        content_cid: vector<u8>,
        price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&kiosk.items) < 8, EMaxItemsReached); // Max 8 items allowed

        let timestamp = clock::timestamp_ms(clock); // Get the current timestamp
        let id = vector::length(&kiosk.items) as u64 + 1; // Generate a new item ID

        let item = KioskItem { id, title, content_cid, price, timestamp };
        vector::push_back(&mut kiosk.items, item); // Add the item to the kiosk
    }

    /// Delete an item from the kiosk by its ID.
    public entry fun delete_item(
        kiosk: &mut UserKiosk,
        item_id: u64,
        ctx: &mut TxContext
    ) {
        assert!(has_item(kiosk, item_id), EItemNotFound); // Ensure the item exists

        let mut index = option::none();
        let mut i = 0;

        while (i < vector::length(&kiosk.items)) {
            if (vector::borrow(&kiosk.items, i).id == item_id) {
                index = option::some(i);
                break;
            };
            i = i + 1;
        };

        let idx = option::get_with_default(&index, 0); // Extract the index using get_with_default
        vector::remove(&mut kiosk.items, idx); // Remove the item from the kiosk
    }

    /// Buy an item from the kiosk by paying the specified price.
    public entry fun buy_item(
        kiosk: &mut UserKiosk,
        item_id: u64,
        payment: Coin<u64>,
        ctx: &mut TxContext
    ) {
        assert!(has_item(kiosk, item_id), EItemNotFound); // Ensure the item exists

        let mut index = option::none();
        let mut i = 0;

        while (i < vector::length(&kiosk.items)) {
            if (vector::borrow(&kiosk.items, i).id == item_id) {
                index = option::some(i);
                break;
            };
            i = i + 1;
        };

        let idx = option::get_with_default(&index, 0);
        let item = vector::borrow(&kiosk.items, idx);

        // Ensure the payment matches the price
        assert!(coin::value(&payment) == item.price, EIncorrectPayment);

        // Merge the payment into the kiosk's balance
        coin::join(&mut kiosk.balance, payment);

        // Remove the item from the kiosk
        vector::remove(&mut kiosk.items, idx);
    }

    /// Withdraw accumulated funds from the kiosk.
    public entry fun withdraw_funds(
        kiosk: &mut UserKiosk,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx); // Get the sender's address
        assert!(is_owner(kiosk, owner), ENotAuthorized); // Ensure only the owner can withdraw

        let amount = coin::value(&kiosk.balance);
        let coin = coin::split(&mut kiosk.balance, amount, ctx); // Split the coin to withdraw the balance

        transfer::public_transfer(coin, owner); // Use public_transfer to send the coin to the owner
    }

    /// Returns all kiosks on-chain
    public fun get_all_kiosks(registry: &KioskRegistry): &vector<ID> {
        &registry.kiosks
    }

    /// Delete the entire kiosk.
    public fun delete_kiosk(
        admin_cap: suimail::admin::AdminCap, // Require AdminCap as an argument
        kiosk: UserKiosk,
        ctx: &mut TxContext
    ): suimail::admin::AdminCap { // Return the AdminCap back to the caller
        let owner = tx_context::sender(ctx); // Get the sender's address
        assert!(suimail::kiosk::is_owner(&kiosk, owner), ENotAuthorized); // Ensure only the owner can delete the kiosk

        // Destructure the kiosk to move the fields
        let UserKiosk { id, balance, items: _, owner: _ } = kiosk;

        // Transfer the remaining balance back to the owner
        transfer::public_transfer(balance, owner);

        // Delete the kiosk by deleting its UID
        object::delete(id);

        admin_cap // Return the AdminCap back to the caller
    }

    public fun verify_kiosk_ownership(registry: &KioskRegistry, kiosk_id: ID, caller: address): bool {
        let mut i = 0;
        while (i < vector::length(&registry.kiosks)) {
            if (vector::borrow(&registry.kiosks, i) == kiosk_id) {
                return *vector::borrow(&registry.owners, i) == caller;
            };
            i = i + 1;
        };
        false // Kiosk not found
    }

    /// Get the number of items in the kiosk.
    public fun get_kiosk_length(kiosk: &UserKiosk): u64 {
        vector::length(&kiosk.items)
    }

    /// Get the total balance accumulated in the kiosk.
    public fun get_kiosk_balance(kiosk: &UserKiosk): u64 {
        coin::value(&kiosk.balance)
    }
}