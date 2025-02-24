module suimail::kiosk {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::vector;
    use std::option::{Self, Option};
    use suimail::nft_staking::{Self, StakingPool, StakedNFT};
    /// Error codes
    const EItemNotFound: u64 = 1;
    const EIncorrectPayment: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EMaxItemsReached: u64 = 4;
    const E_INSUFFICIENT_FUNDS: u64 = 5; // New error for fee validation

    /// Hardcoded Fee Variables
    const KIOSK_CREATION_FEE: u64 = 10_000_000_000; // 10 SUI fee for creating a kiosk
    const SALES_FEE_PERCENTAGE: u64 = 5; // 5% sales fee

    /// Registry to track all kiosks on-chain.
    public struct KioskRegistry has key, store {
        id: UID,                // UID for the registry
        kiosks: vector<ID>,     // List of kiosk IDs
        owners: vector<address>, // List of kiosk owners (parallel to kiosks)
        fee_balance: Balance<SUI>, // Accumulated fees from kiosk creation
        kiosk_creation_fee: u64,   // Fee for creating a kiosk
        owner: address,            // Owner of the registry (deployer)
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
        balance: Balance<SUI>,       // Accumulated balance from sales in SUI
        fee_balance: Balance<SUI>, // Accumulated fees from sales

    }

    /// ✅ Automatically initialize the kiosk registry when the module is published.
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx); // Get the deployer's address
        let registry = KioskRegistry {
            id: object::new(ctx),
            kiosks: vector::empty<ID>(),
            owners: vector::empty<address>(),
            fee_balance: balance::zero<SUI>(),
            kiosk_creation_fee: KIOSK_CREATION_FEE,
            owner: deployer, // Set the deployer as the owner
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
        registry: &mut KioskRegistry,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Ensure the user has paid the correct fee
        assert!(coin::value(&payment) == registry.kiosk_creation_fee, E_INSUFFICIENT_FUNDS);

        // Add the payment to the fee balance
        balance::join(&mut registry.fee_balance, coin::into_balance(payment));

        // Initialize the Kiosk Object
        let kiosk = UserKiosk {
            id: object::new(ctx),
            owner: sender,
            items: vector::empty<KioskItem>(),
            balance: balance::zero<SUI>(),
            fee_balance: balance::zero<SUI>(),
        };

        let kiosk_id = object::id(&kiosk);
        vector::push_back(&mut registry.kiosks, kiosk_id);
        vector::push_back(&mut registry.owners, sender); // Add the owner's address

        // Use `public_share_object` to make the Kiosk public
        transfer::public_share_object(kiosk);
    }


    public entry fun distribute_fees(
    registry: &mut KioskRegistry,
    staking_pool: &mut StakingPool,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == registry.owner, ENotAuthorized);

    let total_fees = balance::value(&registry.fee_balance);
    let mut fees = coin::take(&mut registry.fee_balance, total_fees, ctx); // Declare fees as mutable

    let nft_holder_percentage = nft_staking::calculate_nft_holder_percentage(staking_pool);
    let _owner_percentage = 100 - nft_holder_percentage;

    let nft_holder_share = (total_fees * nft_holder_percentage) / 100;
    let _owner_share = total_fees - nft_holder_share;

    let staked_nfts = nft_staking::get_staked_nfts(staking_pool);
    let mut i = 0;
    while (i < vector::length(staked_nfts)) {
        let staked_nft: &StakedNFT = vector::borrow(staked_nfts, i);
        let tier = nft_staking::get_tier(staked_nft); // Use the accessor function for `tier`
        let owner = nft_staking::get_owner(staked_nft); // Use the accessor function for `owner`
        let percentage = if (tier == 1) {
            nft_staking::get_tier_1_percentage()
        } else if (tier == 2) {
            nft_staking::get_tier_2_percentage()
        } else if (tier == 3) {
            nft_staking::get_tier_3_percentage()
        } else if (tier == 4) {
            nft_staking::get_tier_4_percentage()
        } else {
            0
        };

        let share = (nft_holder_share * percentage) / nft_holder_percentage;
        if (share > 0) {
            let coin = coin::split(&mut fees, share, ctx); // Now fees is mutable
            transfer::public_transfer(coin, owner); // Use the `owner` variable
        };

        i = i + 1;
    };

    if (_owner_share > 0) {
        let owner_coin = coin::split(&mut fees, _owner_share, ctx); // Now fees is mutable
        transfer::public_transfer(owner_coin, registry.owner);
    };

    balance::join(&mut registry.fee_balance, coin::into_balance(fees));
}




    


    /// Publish a new item to the kiosk (owner-only)
    public entry fun publish_item(
        kiosk: &mut UserKiosk,
        title: vector<u8>,
        content_cid: vector<u8>,
        price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_owner(kiosk, sender), ENotAuthorized); // 👈 Added ownership check
        
        assert!(vector::length(&kiosk.items) < 8, EMaxItemsReached);

        let timestamp = clock::timestamp_ms(clock); // Get the current timestamp
        let id = vector::length(&kiosk.items) as u64 + 1; // Generate a new item ID

        let item = KioskItem { id, title, content_cid, price, timestamp };
        vector::push_back(&mut kiosk.items, item); // Add the item to the kiosk
    }

    /// Delete an item from the kiosk (owner-only)
    public entry fun delete_item(
        kiosk: &mut UserKiosk,
        item_id: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_owner(kiosk, sender), ENotAuthorized); // 👈 Added ownership check
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
    mut payment: Coin<SUI>, // Declare payment as mutable
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

    // Calculate the fee
    let fee_amount = (item.price * SALES_FEE_PERCENTAGE) / 100;
    let net_amount = item.price - fee_amount;

    // Split the payment into fee and net amount
    let fee_coin = coin::split(&mut payment, fee_amount, ctx);
    let net_coin = payment;

    // Add the fee to the fee balance
    balance::join(&mut kiosk.fee_balance, coin::into_balance(fee_coin));

    // Add the net payment to the kiosk's balance
    balance::join(&mut kiosk.balance, coin::into_balance(net_coin));

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

    let amount = balance::value(&kiosk.balance);
    let coin = coin::take(&mut kiosk.balance, amount, ctx); // Convert Balance<SUI> to Coin<SUI>

    transfer::public_transfer(coin, owner); // Use public_transfer to send the coin to the owner
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
    balance::value(&kiosk.balance)
}

    public fun get_kiosk_fee_balance(kiosk: &UserKiosk): u64 {
        balance::value(&kiosk.fee_balance)
    }
}