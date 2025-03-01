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
    use std::string::{Self, String};
    use sui::package::{Self, Publisher};
    use sui::display::{Self, Display};
    use suimail::nft_staking::{Self, StakingPool, StakedNFT, NFTCollectionRegistry};

    /// Error codes
    const EItemNotFound: u64 = 1;
    const EIncorrectPayment: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EMaxItemsReached: u64 = 4;
    const E_INSUFFICIENT_FUNDS: u64 = 5;
    const ENoFeesToWithdraw: u64 = 6;

    /// Hardcoded Fee Variables
    const KIOSK_CREATION_FEE: u64 = 10_000_000_000; // 10 SUI fee for creating a kiosk
    const SALES_FEE_PERCENTAGE: u64 = 5; // 5% sales fee

    /// One-Time-Witness for the module
    public struct KIOSK has drop {}

    /// Registry to track all kiosks on-chain
    public struct KioskRegistry has key, store {
        id: UID,
        kiosks: vector<ID>,
        owners: vector<address>,
        fee_balance: Balance<SUI>,
        kiosk_sponsor_fees: Balance<SUI>,
        kiosk_creation_fee: u64,
        owner: address,
    }

    /// Represents a single item in the kiosk
    public struct KioskItem has store, drop {
        id: u64,
        title: vector<u8>,
        content_cid: vector<u8>,
        price: u64,
        timestamp: u64,
    }

    /// KioskNFT with separate fields for better display compatibility
    public struct KioskNFT has key, store {
        id: UID,
        name: String,
        image_url: String,
        description: String,
        price: u64,
        timestamp: u64,
        metadata: vector<u8>, // Optional JSON for additional data
    }

    /// Represents a user's kiosk with items for sale and accumulated balance
    public struct UserKiosk has store, key {
        id: UID,
        owner: address,
        items: vector<KioskItem>,
        balance: Balance<SUI>,
    }

    /// Initialize the kiosk registry and display when the module is published
    fun init(otw: KIOSK, ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        let registry = KioskRegistry {
            id: object::new(ctx),
            kiosks: vector::empty<ID>(),
            owners: vector::empty<address>(),
            fee_balance: balance::zero<SUI>(),
            kiosk_sponsor_fees: balance::zero<SUI>(),
            kiosk_creation_fee: KIOSK_CREATION_FEE,
            owner: deployer,
        };
        transfer::share_object(registry);

        // Claim the Publisher object and set up Display<KioskNFT>
        let publisher = package::claim(otw, ctx);
        let mut display = display::new<KioskNFT>(&publisher, ctx);

        // Define display fields
        display::add(&mut display, string::utf8(b"name"), string::utf8(b"{name}"));
        display::add(&mut display, string::utf8(b"image_url"), string::utf8(b"{image_url}"));
        display::add(&mut display, string::utf8(b"description"), string::utf8(b"{description}"));
        display::add(&mut display, string::utf8(b"project_url"), string::utf8(b"https://suimail.xyz"));
        display::add(&mut display, string::utf8(b"creator"), string::utf8(b"Kiosk Creator"));
        
        // Optional: Add price and timestamp as attributes (not standard, but useful)
        display::add(&mut display, string::utf8(b"price"), string::utf8(b"{price}"));
        display::add(&mut display, string::utf8(b"timestamp"), string::utf8(b"{timestamp}"));

        // Publish the Display
        display::update_version(&mut display);

        transfer::public_transfer(publisher, deployer);
        transfer::public_transfer(display, deployer);
    }

    /// Get the owner of the kiosk
    public fun get_owner(kiosk: &UserKiosk): address {
        kiosk.owner
    }

    /// Check if the given account is the owner of the kiosk
    public fun is_owner(kiosk: &UserKiosk, caller: address): bool {
        caller == kiosk.owner
    }

    /// Check if the kiosk has an item with the given ID
    public fun has_item(kiosk: &UserKiosk, item_id: u64): bool {
        let mut i = 0;
        while (i < vector::length(&kiosk.items)) {
            if (vector::borrow(&kiosk.items, i).id == item_id) {
                return true;
            };
            i = i + 1;
        };
        false
    }

    /// Convert an `ID` to `u64` safely
    fun id_to_numeric(id: &ID): u64 {
        let bytes = object::id_to_bytes(id);
        (bytes[0] as u64) | ((bytes[1] as u64) << 8) | ((bytes[2] as u64) << 16) | ((bytes[3] as u64) << 24) |
        ((bytes[4] as u64) << 32) | ((bytes[5] as u64) << 40) | ((bytes[6] as u64) << 48) | ((bytes[7] as u64) << 56)
    }

    /// Initialize a new kiosk and register it
    public entry fun init_kiosk(
        registry: &mut KioskRegistry,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(coin::value(&payment) == registry.kiosk_creation_fee, E_INSUFFICIENT_FUNDS);
        balance::join(&mut registry.fee_balance, coin::into_balance(payment));

        let kiosk = UserKiosk {
            id: object::new(ctx),
            owner: sender,
            items: vector::empty<KioskItem>(),
            balance: balance::zero<SUI>(),
        };

        let kiosk_id = object::id(&kiosk);
        vector::push_back(&mut registry.kiosks, kiosk_id);
        vector::push_back(&mut registry.owners, sender);
        transfer::public_share_object(kiosk);
    }

    /// Distribute kiosk sponsor fees to NFT holders and registry owner
    public entry fun distribute_fees(
    registry: &mut KioskRegistry,
    staking_pool: &mut StakingPool,
    nft_registry: &nft_staking::NFTCollectionRegistry,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == registry.owner, ENotAuthorized);

    let total_fees_value = balance::value(&registry.kiosk_sponsor_fees);
    assert!(total_fees_value > 0, ENoFeesToWithdraw);

    let mut fees = coin::take(&mut registry.kiosk_sponsor_fees, total_fees_value, ctx);

    let nft_holder_percentage = nft_staking::calculate_nft_holder_percentage(staking_pool);
    let _owner_percentage = 100 - nft_holder_percentage;

    let nft_holder_share = (total_fees_value * nft_holder_percentage) / 100;
    let _owner_share = total_fees_value - nft_holder_share;

    let staked_nfts = nft_staking::get_staked_nfts(staking_pool);
    let total_staked = vector::length(staked_nfts);
    if (total_staked == 0) {
        let owner_coin = coin::split(&mut fees, total_fees_value, ctx);
        transfer::public_transfer(owner_coin, registry.owner);
    } else {
        let mut total_percentage = 0;
        let mut i = 0;
        while (i < total_staked) {
            let staked_nft = vector::borrow(staked_nfts, i);
            let tier = nft_staking::get_tier(staked_nft, nft_registry);
            let percentage = if (tier == 1) { 10000 }
                            else if (tier == 2) { 1000 }
                            else if (tier == 3) { 100 }
                            else if (tier == 4) { 10 }
                            else { 0 };
            total_percentage = total_percentage + percentage;
            i = i + 1;
        };

        i = 0;
        while (i < total_staked) {
            let staked_nft = vector::borrow(staked_nfts, i);
            let tier = nft_staking::get_tier(staked_nft, nft_registry);
            let owner = nft_staking::get_owner(staked_nft);
            let percentage = if (tier == 1) { 10000 }
                            else if (tier == 2) { 1000 }
                            else if (tier == 3) { 100 }
                            else if (tier == 4) { 10 }
                            else { 0 };
            let share = if (total_percentage > 0) {
                (nft_holder_share * percentage) / total_percentage
            } else {
                0
            };
            if (share > 0) {
                let coin = coin::split(&mut fees, share, ctx);
                transfer::public_transfer(coin, owner);
            };
            i = i + 1;
        };

        if (_owner_share > 0) {
            let owner_coin = coin::split(&mut fees, _owner_share, ctx);
            transfer::public_transfer(owner_coin, registry.owner);
        };
    };

    balance::join(&mut registry.kiosk_sponsor_fees, coin::into_balance(fees));
}

    /// Withdraw accumulated kiosk creation fees from the registry
    public entry fun withdraw_registry_fees(
        registry: &mut KioskRegistry,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.owner, ENotAuthorized);

        let total_fees = balance::value(&registry.fee_balance);
        assert!(total_fees > 0, ENoFeesToWithdraw);

        let fees = coin::take(&mut registry.fee_balance, total_fees, ctx);
        transfer::public_transfer(fees, sender);
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
        assert!(is_owner(kiosk, sender), ENotAuthorized);
        assert!(vector::length(&kiosk.items) < 8, EMaxItemsReached);

        let timestamp = clock::timestamp_ms(clock);
        let id = vector::length(&kiosk.items) as u64 + 1;

        let item = KioskItem { id, title, content_cid, price, timestamp };
        vector::push_back(&mut kiosk.items, item);
    }

    /// Delete an item from the kiosk (owner-only)
    public entry fun delete_item(
        kiosk: &mut UserKiosk,
        item_id: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_owner(kiosk, sender), ENotAuthorized);
        assert!(has_item(kiosk, item_id), EItemNotFound);

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
        vector::remove(&mut kiosk.items, idx);
    }

    /// Helper function to convert u64 to string
    fun to_string(num: u64): String {
        let mut s = string::utf8(b"");
        if (num == 0) {
            string::append(&mut s, string::utf8(b"0"));
            return s
        };
        let mut temp = num;
        while (temp > 0) {
            let digit = temp % 10;
            let digit_char = (digit + 48) as u8;
            let digit_str = string::utf8(vector::singleton(digit_char));
            string::append(&mut s, digit_str);
            temp = temp / 10;
        };
        let mut reversed = string::utf8(b"");
        let len = string::length(&s);
        let mut i = 0;
        while (i < len) {
            let char = string::sub_string(&s, len - i - 1, len - i);
            string::append(&mut reversed, char);
            i = i + 1;
        };
        reversed
    }

    /// Function to create metadata JSON as vector<u8> (updated for IPFS)
    fun create_metadata_json(title: vector<u8>, content_cid: vector<u8>, price: u64, timestamp: u64): vector<u8> {
        let mut json = string::utf8(b"{\n");
        string::append(&mut json, string::utf8(b"  \"name\": \""));
        string::append(&mut json, string::utf8(title));
        string::append(&mut json, string::utf8(b"\",\n"));
        string::append(&mut json, string::utf8(b"  \"image\": \"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/")); // Updated to IPFS
        string::append(&mut json, string::utf8(content_cid));
        string::append(&mut json, string::utf8(b"\",\n"));
        string::append(&mut json, string::utf8(b"  \"description\": \"This is a test item.\",\n"));
        string::append(&mut json, string::utf8(b"  \"price\": "));
        string::append(&mut json, to_string(price));
        string::append(&mut json, string::utf8(b",\n"));
        string::append(&mut json, string::utf8(b"  \"timestamp\": "));
        string::append(&mut json, to_string(timestamp));
        string::append(&mut json, string::utf8(b"\n}"));

        let bytes_ref = string::as_bytes(&json);
        let mut owned_bytes = vector::empty<u8>();
        let len = vector::length(bytes_ref);
        let mut i = 0;
        while (i < len) {
            vector::push_back(&mut owned_bytes, *vector::borrow(bytes_ref, i));
            i = i + 1;
        };
        owned_bytes
    }

    /// Buy an item from the kiosk by paying the specified price
    public entry fun buy_item(
        registry: &mut KioskRegistry,
        kiosk: &mut UserKiosk,
        item_id: u64,
        mut payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        assert!(has_item(kiosk, item_id), EItemNotFound);

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
        let item_price = vector::borrow(&kiosk.items, idx).price;
        assert!(coin::value(&payment) == item_price, EIncorrectPayment);

        let fee_amount = (item_price * SALES_FEE_PERCENTAGE) / 100;
        let net_amount = item_price - fee_amount;

        let fee_coin = coin::split(&mut payment, fee_amount, ctx);
        let net_coin = payment;

        balance::join(&mut registry.kiosk_sponsor_fees, coin::into_balance(fee_coin));
        balance::join(&mut kiosk.balance, coin::into_balance(net_coin));

        let item = vector::remove(&mut kiosk.items, idx);

        // Create the NFT with separate fields for display (updated for IPFS)
        let mut image_url = string::utf8(b"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/"); // Updated to IPFS
        string::append(&mut image_url, string::utf8(item.content_cid));
        let metadata_json = create_metadata_json(item.title, item.content_cid, item.price, item.timestamp);
        let nft = KioskNFT {
            id: object::new(ctx),
            name: string::utf8(item.title),
            image_url,
            description: string::utf8(b"This is a test item."),
            price: item.price,
            timestamp: item.timestamp,
            metadata: metadata_json
        };

        transfer::public_transfer(nft, tx_context::sender(ctx));
    }

    /// Withdraw accumulated funds from the kiosk
    public entry fun withdraw_funds(
        kiosk: &mut UserKiosk,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        assert!(is_owner(kiosk, owner), ENotAuthorized);

        let amount = balance::value(&kiosk.balance);
        let coin = coin::take(&mut kiosk.balance, amount, ctx);
        transfer::public_transfer(coin, owner);
    }

    public fun verify_kiosk_ownership(registry: &KioskRegistry, kiosk_id: ID, caller: address): bool {
        let mut i = 0;
        while (i < vector::length(&registry.kiosks)) {
            if (vector::borrow(&registry.kiosks, i) == &kiosk_id) {
                return *vector::borrow(&registry.owners, i) == caller;
            };
            i = i + 1;
        };
        false
    }

    /// Get the number of items in the kiosk
    public fun get_kiosk_length(kiosk: &UserKiosk): u64 {
        vector::length(&kiosk.items)
    }

    /// Get the total balance accumulated in the kiosk
    public fun get_kiosk_balance(kiosk: &UserKiosk): u64 {
        balance::value(&kiosk.balance)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let otw = KIOSK {};
        init(otw, ctx);
    }
}