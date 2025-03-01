module suimail::nft_staking {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::string::{Self, String};
    use std::vector;
    use sui::package::{Self, Publisher};
    use sui::display::{Self, Display};
    use sui::table::{Self, Table};
    use std::option::{Self, Option};
    use sui::event;

    /// Error codes
    const ENotAuthorized: u64 = 1;
    const EInvalidTier: u64 = 2;
    const EMaxTierLimitReached: u64 = 3;
    const EIncorrectPayment: u64 = 4;
    const EItemNotFound: u64 = 5;

    /// NFT Tiers and Percentages (scaled by 1000 for precision)
    const TIER_1_PERCENTAGE: u64 = 1000; // 1%
    const TIER_2_PERCENTAGE: u64 = 100;  // 0.1%
    const TIER_3_PERCENTAGE: u64 = 10;   // 0.01%
    const TIER_4_PERCENTAGE: u64 = 1;    // 0.001%

    const TIER_1_MAX: u64 = 10;    // Highest tier, smallest max
    const TIER_2_MAX: u64 = 100;
    const TIER_3_MAX: u64 = 1000;
    const TIER_4_MAX: u64 = 10000; // Lowest tier, largest max

    const TIER_1_IMAGE_URL: vector<u8> = b"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/bafybeie3tr2dlverq42uhyzce2zecqkndbwxa2pc5sz3yzy35qocwpmjfu";
    const TIER_2_IMAGE_URL: vector<u8> = b"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/bafybeigsfggeajqsg7pzemunarwbw24rc32gijyohqrolofi4mmcgveaom";
    const TIER_3_IMAGE_URL: vector<u8> = b"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/bafkreigpkeztxhquoiiocpf5l5gkkl376rdr3ttukabr7xueopvbh6lqfq";
    const TIER_4_IMAGE_URL: vector<u8> = b"https://bronze-quiet-cuckoo-704.mypinata.cloud/ipfs/bafkreia5jj6zff2simjagmimesoeljqzvma3hxfiu5lwunwbmqxjstps3y";

    /// One-Time-Witness for the module
    public struct NFT_STAKING has drop {}

    /// Represents an NFT with a tier
    public struct NFT has key, store {
        id: UID,
        owner: address,
        tier: u8,
        donation_amount: u64,
        name: String,
        image_url: String,
        description: String,
    }

    /// Ticket issued when staking an NFT, redeemable for the original NFT
    public struct StakingTicket has key, store {
        id: UID,
        nft_id: ID,
        owner: address,
    }

    /// Registry to track all staked NFTs and tier counts
    public struct NFTCollectionRegistry has key {
        id: UID,
        nfts: Table<ID, NFT>, // Stores NFTs during staking
        tier_counts: vector<u64>, // [tier1_count, tier2_count, tier3_count, tier4_count]
        owner: address,
    }

    /// Represents a staked NFT
    public struct StakedNFT has key, store {
        id: UID,
        nft_id: ID,
        owner: address,
    }

    /// Represents the staking pool
    public struct StakingPool has key {
        id: UID,
        staked_nfts: vector<StakedNFT>,
        total_fees: Balance<SUI>,
        donated_balance: Balance<SUI>,
        owner: address,
    }

    /// Collection object for Sponsor NFTs
    public struct SponsorNFTCollection has key {
        id: UID,
        name: String,
        description: String,
        total_minted: u64,
        minted_nfts: Table<ID, bool>, // Tracks all minted NFT IDs
    }

    /// Event emitted when an NFT is minted into the collection
    public struct NFTMintedEvent has copy, drop {
        nft_id: ID,
        tier: u8,
        sender: address,
    }

    /// Calculate the NFT holder percentage based on the staking pool
    public fun calculate_nft_holder_percentage(pool: &StakingPool): u64 {
        let total_staked = vector::length(&pool.staked_nfts);
        if (total_staked == 0) return 0;
        let total_donated = balance::value(&pool.donated_balance);
        if (total_donated == 0) return 0;
        (total_staked * 100) / total_donated
    }

    /// Get the tier of a staked NFT
    public fun get_tier(staked_nft: &StakedNFT, registry: &NFTCollectionRegistry): u8 {
        let nft = table::borrow(&registry.nfts, staked_nft.nft_id);
        nft.tier
    }

    /// Get the owner of a staked NFT
    public fun get_owner(staked_nft: &StakedNFT): address {
        staked_nft.owner
    }

    /// Get the list of staked NFTs
    public fun get_staked_nfts(pool: &StakingPool): &vector<StakedNFT> {
        &pool.staked_nfts
    }

    /// Public functions to expose constant values
    public fun get_tier_1_percentage(): u64 { TIER_1_PERCENTAGE }
    public fun get_tier_2_percentage(): u64 { TIER_2_PERCENTAGE }
    public fun get_tier_3_percentage(): u64 { TIER_3_PERCENTAGE }
    public fun get_tier_4_percentage(): u64 { TIER_4_PERCENTAGE }

    /// Initialize the staking pool, registry, and collection
    fun init(otw: NFT_STAKING, ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);

        let staking_pool = StakingPool {
            id: object::new(ctx),
            staked_nfts: vector::empty<StakedNFT>(),
            total_fees: balance::zero<SUI>(),
            donated_balance: balance::zero<SUI>(),
            owner: deployer,
        };
        transfer::share_object(staking_pool);

        let registry = NFTCollectionRegistry {
            id: object::new(ctx),
            nfts: table::new(ctx),
            tier_counts: vector[0, 0, 0, 0],
            owner: deployer,
        };
        transfer::share_object(registry);

        let collection = SponsorNFTCollection {
            id: object::new(ctx),
            name: string::utf8(b"Sponsor NFT Collection"),
            description: string::utf8(b"A collection of NFTs representing sponsorship donations for SuiMail"),
            total_minted: 0,
            minted_nfts: table::new(ctx),
        };
        transfer::share_object(collection);

        let publisher = package::claim(otw, ctx);
        let mut display = display::new<NFT>(&publisher, ctx);
        display::add(&mut display, string::utf8(b"name"), string::utf8(b"{name}"));
        display::add(&mut display, string::utf8(b"image_url"), string::utf8(b"{image_url}"));
        display::add(&mut display, string::utf8(b"description"), string::utf8(b"{description}"));
        display::add(&mut display, string::utf8(b"project_url"), string::utf8(b"https://suimail.xyz"));
        display::add(&mut display, string::utf8(b"creator"), string::utf8(b"SuiMail Team"));
        display::add(&mut display, string::utf8(b"tier"), string::utf8(b"{tier}"));
        display::add(&mut display, string::utf8(b"donation_amount"), string::utf8(b"{donation_amount}"));
        display::add(&mut display, string::utf8(b"collection"), string::utf8(b"Sponsor NFT Collection"));
        display::update_version(&mut display);

        transfer::public_transfer(publisher, deployer);
        transfer::public_transfer(display, deployer);
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

    /// Calculate the tier based on the donation amount
    fun calculate_tier(donation_amount: u64): u8 {
        if (donation_amount >= 50_000_000_000_000) 1 // 50,000 SUI+
        else if (donation_amount >= 5_000_000_000_000) 2 // 5,000 - 49,999 SUI
        else if (donation_amount >= 1_000_000_000_000) 3 // 1,000 - 4,999 SUI
        else 4 // 10 - 999 SUI
    }

    /// Mint a new sponsor NFT and add to collection
    public entry fun mint_sponsor_nft(
        collection: &mut SponsorNFTCollection,
        registry: &mut NFTCollectionRegistry,
        pool: &mut StakingPool,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let donation_amount = coin::value(&payment);

        assert!(donation_amount >= 10_000_000_000, EIncorrectPayment); // 10 SUI min
        assert!(donation_amount <= 50_000_000_000_000, EIncorrectPayment); // 50,000 SUI max

        let tier = calculate_tier(donation_amount);
        let tier_index = (tier - 1) as u64;
        let tier_count = *vector::borrow(&registry.tier_counts, tier_index);

        if (tier == 1) assert!(tier_count < TIER_1_MAX, EMaxTierLimitReached)
        else if (tier == 2) assert!(tier_count < TIER_2_MAX, EMaxTierLimitReached)
        else if (tier == 3) assert!(tier_count < TIER_3_MAX, EMaxTierLimitReached)
        else assert!(tier_count < TIER_4_MAX, EMaxTierLimitReached);

        *vector::borrow_mut(&mut registry.tier_counts, tier_index) = tier_count + 1;

        let mut name = string::utf8(b"Sponsor NFT Tier ");
        string::append(&mut name, to_string(tier as u64));
        let image_url = string::utf8(if (tier == 1) TIER_1_IMAGE_URL
                                    else if (tier == 2) TIER_2_IMAGE_URL
                                    else if (tier == 3) TIER_3_IMAGE_URL
                                    else TIER_4_IMAGE_URL);
        let mut description = string::utf8(b"An NFT representing a sponsorship donation at tier ");
        string::append(&mut description, to_string(tier as u64));

        let nft = NFT {
            id: object::new(ctx),
            owner: sender,
            tier,
            donation_amount,
            name,
            image_url,
            description,
        };

        let nft_id = object::id(&nft);
        table::add(&mut collection.minted_nfts, nft_id, true);
        collection.total_minted = collection.total_minted + 1;

        event::emit(NFTMintedEvent {
            nft_id,
            tier,
            sender,
        });

        transfer::public_transfer(nft, sender);
        balance::join(&mut pool.donated_balance, coin::into_balance(payment));
    }

    /// Edit a sponsor NFT to add more SUI and upgrade its tier
    public entry fun edit_sponsor_nft(
        collection: &mut SponsorNFTCollection,
        registry: &mut NFTCollectionRegistry,
        pool: &mut StakingPool,
        nft: &mut NFT,
        additional_payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let additional_amount = coin::value(&additional_payment);

        assert!(nft.owner == sender, ENotAuthorized);
        let nft_id = object::id(nft);

        let new_donation_amount = nft.donation_amount + additional_amount;
        assert!(new_donation_amount <= 50_000_000_000_000, EIncorrectPayment);

        let new_tier = calculate_tier(new_donation_amount);

        if (new_tier != nft.tier) {
            let tier_index = (new_tier - 1) as u64;
            let tier_count = *vector::borrow(&registry.tier_counts, tier_index);

            if (new_tier == 1) assert!(tier_count < TIER_1_MAX, EMaxTierLimitReached)
            else if (new_tier == 2) assert!(tier_count < TIER_2_MAX, EMaxTierLimitReached)
            else if (new_tier == 3) assert!(tier_count < TIER_3_MAX, EMaxTierLimitReached)
            else assert!(tier_count < TIER_4_MAX, EMaxTierLimitReached);

            let old_tier_index = (nft.tier - 1) as u64;
            *vector::borrow_mut(&mut registry.tier_counts, old_tier_index) = *vector::borrow(&registry.tier_counts, old_tier_index) - 1;
            *vector::borrow_mut(&mut registry.tier_counts, tier_index) = tier_count + 1;

            nft.tier = new_tier;
            let mut name = string::utf8(b"Sponsor NFT Tier ");
            string::append(&mut name, to_string(new_tier as u64));
            nft.name = name;
            nft.image_url = string::utf8(if (new_tier == 1) TIER_1_IMAGE_URL
                                        else if (new_tier == 2) TIER_2_IMAGE_URL
                                        else if (new_tier == 3) TIER_3_IMAGE_URL
                                        else TIER_4_IMAGE_URL);
            let mut description = string::utf8(b"An NFT representing a sponsorship donation at tier ");
            string::append(&mut description, to_string(new_tier as u64));
            nft.description = description;
        };

        nft.donation_amount = new_donation_amount;
        balance::join(&mut pool.donated_balance, coin::into_balance(additional_payment));
    }

    /// Withdraw all donated funds (owner only)
    public entry fun withdraw_funds(pool: &mut StakingPool, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(sender == pool.owner, ENotAuthorized);

        let amount = balance::value(&pool.donated_balance);
        assert!(amount > 0, EIncorrectPayment);

        let withdrawn_funds = balance::split(&mut pool.donated_balance, amount);
        let coin = coin::from_balance(withdrawn_funds, ctx);
        transfer::public_transfer(coin, sender);
    }

    /// Stake an NFT into the staking pool
    public entry fun stake_nft(
        pool: &mut StakingPool,
        registry: &mut NFTCollectionRegistry,
        nft: NFT,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(nft.owner == sender, ENotAuthorized);

        let nft_id = object::id(&nft);
        let tier = nft.tier;
        assert!(tier >= 1 && tier <= 4, EInvalidTier);

        let staked_nft = StakedNFT {
            id: object::new(ctx),
            nft_id,
            owner: sender,
        };

        vector::push_back(&mut pool.staked_nfts, staked_nft);
        table::add(&mut registry.nfts, nft_id, nft);

        let ticket = StakingTicket {
            id: object::new(ctx),
            nft_id,
            owner: sender,
        };
        transfer::public_transfer(ticket, sender);
    }

    /// Unstake an NFT from the staking pool
    public entry fun unstake_nft(
        pool: &mut StakingPool,
        registry: &mut NFTCollectionRegistry,
        ticket: StakingTicket,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(ticket.owner == sender, ENotAuthorized);

        let nft_id = ticket.nft_id;
        let mut index = option::none();
        let mut i = 0;

        while (i < vector::length(&pool.staked_nfts)) {
            let staked_nft_ref = vector::borrow(&pool.staked_nfts, i);
            if (staked_nft_ref.nft_id == nft_id) {
                assert!(staked_nft_ref.owner == sender, ENotAuthorized);
                index = option::some(i);
                break;
            };
            i = i + 1;
        };

        assert!(option::is_some(&index), EItemNotFound);
        let idx = option::extract(&mut index);

        let StakedNFT { id, nft_id, owner: _ } = vector::remove(&mut pool.staked_nfts, idx);
        object::delete(id);

        let mut nft = table::remove(&mut registry.nfts, nft_id);
        nft.owner = sender;
        transfer::public_transfer(nft, sender);

        let StakingTicket { id, nft_id: _, owner: _ } = ticket;
        object::delete(id);
    }

    /// Getter functions for public access
    public fun get_tier_counts(registry: &NFTCollectionRegistry): &vector<u64> {
        &registry.tier_counts
    }

    public fun is_valid_nft(registry: &NFTCollectionRegistry, nft_id: &ID): bool {
        table::contains(&registry.nfts, *nft_id)
    }

    public fun get_collection_total_minted(collection: &SponsorNFTCollection): u64 {
        collection.total_minted
    }

    public fun is_nft_in_collection(collection: &SponsorNFTCollection, nft_id: &ID): bool {
        table::contains(&collection.minted_nfts, *nft_id)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let otw = NFT_STAKING {};
        init(otw, ctx);
    }
}