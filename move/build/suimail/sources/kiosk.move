module suimail::kiosk {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::vector;
    use std::option::{Self, Option};
    use suimail::admin::AdminCap;

    /// Error codes
    const EItemNotFound: u64 = 1;
    const EIncorrectPayment: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EMaxItemsReached: u64 = 4;

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

    /// Initialize a new kiosk for the calling account.
    public entry fun init_kiosk(ctx: &mut TxContext) {
        let id = object::new(ctx); // Create a new UID for the kiosk
        let owner = tx_context::sender(ctx); // Get the sender's address
        let balance = coin::zero(ctx); // Initialize the balance to zero SUI

        let kiosk = UserKiosk {
            id,
            owner,
            items: vector::empty<KioskItem>(),
            balance
        };
        transfer::transfer(kiosk, owner); // Transfer the kiosk to the sender's storage
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

    /// Get the number of items in the kiosk.
    public fun get_kiosk_length(kiosk: &UserKiosk): u64 {
        vector::length(&kiosk.items)
    }

    /// Get the total balance accumulated in the kiosk.
    public fun get_kiosk_balance(kiosk: &UserKiosk): u64 {
        coin::value(&kiosk.balance)
    }
}
