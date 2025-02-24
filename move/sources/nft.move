module suimail::nft_staking {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    use std::vector;
    use std::option::{Self, Option};

    /// Error codes
    const ENotAuthorized: u64 = 1;
    const EInvalidTier: u64 = 2;
    const EMaxTierLimitReached: u64 = 3;
    const EIncorrectPayment: u64 = 4; // Incorrect payment amount
    const EItemNotFound: u64 = 5; // NFT not found

    /// NFT Tiers and Percentages
    const TIER_1_PERCENTAGE: u64 = 1; // 1%
    const TIER_2_PERCENTAGE: u64 = 1; // 0.1%
    const TIER_3_PERCENTAGE: u64 = 1; // 0.01%
    const TIER_4_PERCENTAGE: u64 = 1; // 0.001%

    const TIER_1_MAX: u64 = 10;
    const TIER_2_MAX: u64 = 100;
    const TIER_3_MAX: u64 = 1000;
    const TIER_4_MAX: u64 = 10000;

    const TIER_1_IMAGE_URL: vector<u8> = b"https://ipfs.io/ipfs/QmTier1ImageCID";
    const TIER_2_IMAGE_URL: vector<u8> = b"https://ipfs.io/ipfs/QmTier2ImageCID";
    const TIER_3_IMAGE_URL: vector<u8> = b"https://ipfs.io/ipfs/QmTier3ImageCID";
    const TIER_4_IMAGE_URL: vector<u8> = b"https://ipfs.io/ipfs/QmTier4ImageCID";

    // Public functions to expose constant values
    public fun get_tier_1_percentage(): u64 {
        TIER_1_PERCENTAGE
    }

    public fun get_tier_2_percentage(): u64 {
        TIER_2_PERCENTAGE
    }

    public fun get_tier_3_percentage(): u64 {
        TIER_3_PERCENTAGE
    }

    public fun get_tier_4_percentage(): u64 {
        TIER_4_PERCENTAGE
    }

    // Public accessor function for the `tier` field
    public fun get_tier(staked_nft: &StakedNFT): u8 {
        staked_nft.tier
    }

    // Public accessor function for the `owner` field
    public fun get_owner(staked_nft: &StakedNFT): address {
        staked_nft.owner
    }

    /// Represents an NFT with a tier
    public struct NFT has store, key {
        id: UID,
        owner: address,
        tier: u8, // 1, 2, 3, or 4
        donation_amount: u64, // Total SUI donated for this NFT
        image_url: vector<u8>, // URL or CID of the image/GIF
    }

    /// Represents a staked NFT
    public struct StakedNFT has store, key {
        id: UID,
        nft: NFT, // Store the original NFT
        owner: address,
        tier: u8,
        donation_amount: u64,
        image_url: vector<u8>,
    }

    /// Represents the staking pool
    public struct StakingPool has key {
        id: UID,
        staked_nfts: vector<StakedNFT>, // List of staked NFTs
        total_fees: Balance<SUI>,       // Total fees accumulated for distribution
        donated_balance: Balance<SUI>,  // Total donated SUI
        tier_counts: vector<u64>,       // Count of NFTs in each tier [Tier 1, Tier 2, Tier 3, Tier 4]
        owner: address,                 // Owner of the staking pool
    }

    /// Initialize the staking pool
    fun init(ctx: &mut TxContext) {
        let staking_pool = StakingPool {
            id: object::new(ctx),
            staked_nfts: vector::empty<StakedNFT>(),
            total_fees: balance::zero<SUI>(),
            donated_balance: balance::zero<SUI>(), // Initialize donated balance to 0
            tier_counts: vector[0, 0, 0, 0], // Initialize tier counts to 0
            owner: tx_context::sender(ctx), // Set the deployer as the owner
        };
        transfer::share_object(staking_pool); // Make the staking pool publicly accessible
    }

    // Public function to access staked_nfts
    public fun get_staked_nfts(pool: &StakingPool): &vector<StakedNFT> {
        &pool.staked_nfts
    }

    /// Mint a new sponsor NFT
    public entry fun mint_sponsor_nft(
        pool: &mut StakingPool,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let donation_amount = coin::value(&payment);

        // Ensure the donation meets the minimum requirement (10 SUI)
        assert!(donation_amount >= 10_000_000_000, EIncorrectPayment); // 10 SUI in MIST

        // Ensure the donation does not exceed the maximum (50,000 SUI)
        assert!(donation_amount <= 50_000_000_000_000, EIncorrectPayment); // 50,000 SUI in MIST

        // Ensure the Tier 4 limit has not been reached
        let tier_4_count = *vector::borrow(&pool.tier_counts, 3);
        assert!(tier_4_count < TIER_4_MAX, EMaxTierLimitReached);

        // Create the NFT with Tier 4
        let nft = NFT {
            id: object::new(ctx),
            owner: sender,
            tier: 4, // Start at Tier 4
            donation_amount: donation_amount,
            image_url: TIER_4_IMAGE_URL,
        };

        // Add the NFT to the staking pool
        stake_nft(pool, nft, ctx);

        // Transfer the payment to the donated balance
        balance::join(&mut pool.donated_balance, coin::into_balance(payment));
    }

    
    /// Calculate the tier based on the donation amount
    fun calculate_tier(donation_amount: u64): u8 {
        if (donation_amount >= 50_000_000_000_000) { // 50,000 SUI or more (Tier 1)
            1
        } else if (donation_amount >= 5_000_000_000_000) { // 5,000 - 49,999 SUI (Tier 2)
            2
        } else if (donation_amount >= 1_000_000_000_000) { // 1,000 - 4,999 SUI (Tier 3)
            3
        } else if (donation_amount >= 10_000_000_000) { // 10 - 999 SUI (Tier 4)
            4
        } else {
            // If the donation amount is below the minimum (10 SUI), return Tier 4 as a default
            4
        }
    }


    /// Withdraw the donated SUI (owner-only)
    public entry fun withdraw_donated_balance(
        pool: &mut StakingPool,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == pool.owner, ENotAuthorized); // Ensure only the owner can withdraw

        let donated_amount = balance::value(&pool.donated_balance);
        let donated_coin = coin::take(&mut pool.donated_balance, donated_amount, ctx);

        // Transfer the donated SUI to the owner
        transfer::public_transfer(donated_coin, sender);
    }

    /// Edit a sponsor NFT to add more SUI and upgrade its tier
public entry fun edit_sponsor_nft(
    pool: &mut StakingPool,
    staked_nft: &mut StakedNFT, // NFT object passed from the front end
    additional_payment: Coin<SUI>,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    let additional_amount = coin::value(&additional_payment);

    // Ensure the sender owns the NFT
    assert!(staked_nft.owner == sender, ENotAuthorized);

    // Ensure the additional donation does not exceed the maximum (50,000 SUI total)
    assert!(staked_nft.donation_amount + additional_amount <= 50_000_000_000_000, EIncorrectPayment); // 50,000 SUI in MIST

    // Update the donation amount
    staked_nft.donation_amount = staked_nft.donation_amount + additional_amount;

    // Check if the NFT qualifies for a higher tier
    let new_tier = calculate_tier(staked_nft.donation_amount);
    if (new_tier != staked_nft.tier) {
        // Ensure the new tier's limit has not been reached
        let tier_index = (new_tier - 1) as u64;
        let tier_count = *vector::borrow(&pool.tier_counts, tier_index);
        if (new_tier == 1) {
            assert!(tier_count < TIER_1_MAX, EMaxTierLimitReached);
        } else if (new_tier == 2) {
            assert!(tier_count < TIER_2_MAX, EMaxTierLimitReached);
        } else if (new_tier == 3) {
            assert!(tier_count < TIER_3_MAX, EMaxTierLimitReached);
        } else if (new_tier == 4) {
            assert!(tier_count < TIER_4_MAX, EMaxTierLimitReached);
        } else {
            abort EInvalidTier;
        };

        // Update the NFT's tier
        staked_nft.tier = new_tier;

        // Update the image URL based on the new tier
        if (new_tier == 1) {
            staked_nft.image_url = TIER_1_IMAGE_URL;
        } else if (new_tier == 2) {
            staked_nft.image_url = TIER_2_IMAGE_URL;
        } else if (new_tier == 3) {
            staked_nft.image_url = TIER_3_IMAGE_URL;
        } else {
            staked_nft.image_url = TIER_4_IMAGE_URL; // Default to Tier 4 image
        };

        // Update the tier counts
        let old_tier_index = (staked_nft.tier - 1) as u64;
        let old_tier_count = *vector::borrow(&pool.tier_counts, old_tier_index);
        *vector::borrow_mut(&mut pool.tier_counts, old_tier_index) = old_tier_count - 1;

        *vector::borrow_mut(&mut pool.tier_counts, tier_index) = tier_count + 1;
    };

    // Transfer the additional payment to the donated balance
    balance::join(&mut pool.donated_balance, coin::into_balance(additional_payment));
}

    /// Stake an NFT into the staking pool
    public entry fun stake_nft(
        pool: &mut StakingPool,
        nft: NFT,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(nft.owner == sender, ENotAuthorized); // Ensure the sender owns the NFT

        let tier = nft.tier;
        assert!(tier >= 1 && tier <= 4, EInvalidTier); // Ensure the tier is valid

        // Check if the tier limit has been reached
        let tier_index = (tier - 1) as u64;
        let tier_count = *vector::borrow(&pool.tier_counts, tier_index);
        if (tier == 1) {
            assert!(tier_count < TIER_1_MAX, EMaxTierLimitReached);
        } else if (tier == 2) {
            assert!(tier_count < TIER_2_MAX, EMaxTierLimitReached);
        } else if (tier == 3) {
            assert!(tier_count < TIER_3_MAX, EMaxTierLimitReached);
        } else if (tier == 4) {
            assert!(tier_count < TIER_4_MAX, EMaxTierLimitReached);
        } else {
            abort EInvalidTier;
        };

        // Increment the tier count
        *vector::borrow_mut(&mut pool.tier_counts, tier_index) = tier_count + 1;

        // Extract fields from the NFT before moving it
        let NFT { id, owner: _, tier: _, donation_amount, image_url } = nft;

        // Delete the UID of the original NFT
        object::delete(id);

        // Create a staked NFT object with a new UID
        let staked_nft = StakedNFT {
            id: object::new(ctx), // Generate a new UID
            nft: NFT {
                id: object::new(ctx), // Generate a new UID for the inner NFT
                owner: sender,
                tier: tier,
                donation_amount: donation_amount,
                image_url: image_url,
            },
            owner: sender,
            tier: tier,
            donation_amount: donation_amount,
            image_url: image_url,
        };

        // Add the staked NFT to the pool
        vector::push_back(&mut pool.staked_nfts, staked_nft);
    }

    /// Calculate the total percentage allocated to NFT holders
    public fun calculate_nft_holder_percentage(pool: &StakingPool): u64 {
        let mut total_percentage = 0;

        let tier_1_count = *vector::borrow(&pool.tier_counts, 0);
        let tier_2_count = *vector::borrow(&pool.tier_counts, 1);
        let tier_3_count = *vector::borrow(&pool.tier_counts, 2);
        let tier_4_count = *vector::borrow(&pool.tier_counts, 3);

        total_percentage = total_percentage + (tier_1_count * TIER_1_PERCENTAGE);
        total_percentage = total_percentage + (tier_2_count * TIER_2_PERCENTAGE);
        total_percentage = total_percentage + (tier_3_count * TIER_3_PERCENTAGE);
        total_percentage = total_percentage + (tier_4_count * TIER_4_PERCENTAGE);

        total_percentage
    }

    /// Unstake an NFT from the staking pool
    public entry fun unstake_nft(
        pool: &mut StakingPool,
        nft_id: ID,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let mut index = option::none();
        let mut i = 0;

        // Find the staked NFT by ID
        while (i < vector::length(&pool.staked_nfts)) {
            let staked_nft_ref = vector::borrow(&pool.staked_nfts, i);
            if (object::id(&staked_nft_ref.nft) == nft_id) {
                assert!(staked_nft_ref.owner == sender, ENotAuthorized);
                index = option::some(i);
                break;
            };
            i = i + 1;
        };

        let idx = option::get_with_default(&index, 0);
        let StakedNFT { id, nft, owner: _, tier, donation_amount: _, image_url: _ } = vector::remove(&mut pool.staked_nfts, idx);

        // Decrement the tier count
        let tier_index = (tier - 1) as u64;
        let tier_count = *vector::borrow(&pool.tier_counts, tier_index);
        *vector::borrow_mut(&mut pool.tier_counts, tier_index) = tier_count - 1;

        // Delete the UID of the StakedNFT
        object::delete(id);

        // Transfer the original NFT back to the owner
        transfer::public_transfer(nft, sender);
    }
}