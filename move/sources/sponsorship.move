module suimail::sponsorship {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::string::{Self, String};

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_FUNDS: u64 = 2;
    const E_SPONSORSHIP_CLOSED: u64 = 3;

    // Sponsorship tiers
    const TIER_1_THRESHOLD: u64 = 10_000; // 10,000 SUI
    const TIER_2_THRESHOLD: u64 = 5_000;  // 5,000 SUI
    const TIER_3_THRESHOLD: u64 = 1_000;  // 1,000 SUI
    const TIER_4_THRESHOLD: u64 = 10;     // 10 SUI

    // Struct to represent a Sponsor NFT
    public struct SponsorNFT has key, store {
        id: UID,
        sponsor: address, // Address of the sponsor
        amount: u64,      // Amount of SUI sponsored
        image_url: String, // URL of the NFT image
    }

    // Struct to manage the Sponsors Registry
    public struct SponsorsRegistry has key {
        id: UID,
        total_sponsored: Balance<SUI>, // Total SUI sponsored (as a Balance)
        sponsors: vector<SponsorNFT>, // List of sponsor NFTs
        creator: address, // Address of the creator (only they can withdraw funds)
        sponsorship_open: bool, // Whether sponsorship is still open
    }

    // Initialize the Sponsors Registry
    fun init(ctx: &mut TxContext) {
        let registry = SponsorsRegistry {
            id: object::new(ctx),
            total_sponsored: balance::zero<SUI>(), // Initialize with zero balance
            sponsors: vector::empty<SponsorNFT>(),
            creator: tx_context::sender(ctx),
            sponsorship_open: true,
        };
        transfer::share_object(registry); // Make the registry publicly accessible
    }

    // Mint a Sponsor NFT with an image URL
    public entry fun mint_sponsor_nft(
        registry: &mut SponsorsRegistry,
        payment: Coin<SUI>,
        image_url: String, // URL of the NFT image
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Ensure sponsorship is still open
        assert!(registry.sponsorship_open, E_SPONSORSHIP_CLOSED);

        // Ensure the payment is valid
        let amount = coin::value(&payment);
        assert!(amount > 0, E_INSUFFICIENT_FUNDS);

        // Create the Sponsor NFT with the image URL
        let sponsor_nft = SponsorNFT {
            id: object::new(ctx),
            sponsor: sender,
            amount: amount,
            image_url: image_url,
        };

        // Add the NFT to the registry
        vector::push_back(&mut registry.sponsors, sponsor_nft);

        // Add the payment to the total sponsored balance
        balance::join(&mut registry.total_sponsored, coin::into_balance(payment));
    }

    // Close sponsorship (only callable by the creator)
    public entry fun close_sponsorship(
        registry: &mut SponsorsRegistry,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.creator, E_NOT_AUTHORIZED); // Only the creator can close sponsorship
        registry.sponsorship_open = false;
    }

    // Withdraw sponsored funds (only callable by the creator)
    public entry fun withdraw_funds(
        registry: &mut SponsorsRegistry,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.creator, E_NOT_AUTHORIZED); // Only the creator can withdraw funds

        // Get the total sponsored amount
        let amount = balance::value(&registry.total_sponsored);

        // Withdraw the funds as a Coin<SUI>
        let funds = coin::take(&mut registry.total_sponsored, amount, ctx);

        // Transfer the funds to the creator
        transfer::public_transfer(funds, sender);
    }

    // Get the total amount of SUI sponsored
    public fun get_total_sponsored(registry: &SponsorsRegistry): u64 {
        balance::value(&registry.total_sponsored)
    }

    // Get the list of sponsor NFTs
    public fun get_sponsors(registry: &SponsorsRegistry): &vector<SponsorNFT> {
        &registry.sponsors
    }

    // Determine the tier of a sponsor based on their sponsored amount
    public fun get_sponsor_tier(amount: u64): u8 {
        if (amount >= TIER_1_THRESHOLD) {
            1 // Tier 1: Mythical
        } else if (amount >= TIER_2_THRESHOLD) {
            2 // Tier 2: Epic
        } else if (amount >= TIER_3_THRESHOLD) {
            3 // Tier 3: Rare
        } else if (amount >= TIER_4_THRESHOLD) {
            4 // Tier 4: Common
        } else {
            0 // Not eligible
        }
    }
}