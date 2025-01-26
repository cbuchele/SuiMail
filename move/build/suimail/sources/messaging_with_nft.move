module suimail::messaging_with_nft {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::vector;
    use std::option::{Self, Option};

    /// Error codes
    const E_NO_NFT_ATTACHED: u64 = 1;
    const E_NO_CLAIM_PRICE: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_BANK_EXISTS: u64 = 4;
    const E_ITEM_NOT_FOUND: u64 = 5;
    const E_NOT_AUTHORIZED: u64 = 6;

    /// Hardcoded Fee Variables
    const MESSAGE_FEE: u64 = 100_000_000; // 0.1 SUI fee

    /// Represents a message with optional NFT attachment and claim price.
    public struct MessageWithNFT has store, drop {
        id: u64,
        sender: address,
        receiver: address,
        cid: vector<u8>,               // Content ID of the message
        timestamp: u64,                // Timestamp when the message was sent
        nft_object_id: option::Option<address>, // Address of the NFT, if attached
        claim_price: option::Option<u64>,       // Price to claim the NFT, if any
    }

    /// Represents a mailbox that stores messages for a user.
    public struct Mailbox has key, store {
        id: UID,                          // Unique ID for the mailbox
        owner: address,                   // Owner of the mailbox
        messages: vector<MessageWithNFT>, // List of messages in the mailbox
    }

    /// Represents an admin capability object.
    public struct AdminCap has store, key {
        id: UID,
    }

    /// Represents a bank object for collecting fees.
    public struct Bank has store, key {
        id: UID,       // Unique ID for the bank
        admin: address, // Admin who can withdraw fees
        balance: Coin<u64>, // Collected fees
    }

    /// Initialize a new mailbox for the calling account.
    public entry fun init_mailbox(ctx: &mut TxContext) {
        let id = object::new(ctx); // Create a new UID
        let owner = tx_context::sender(ctx); // Get the sender's address
        let mailbox = Mailbox {
            id,
            owner,
            messages: vector::empty<MessageWithNFT>(),
        };
        transfer::public_share_object(mailbox); // Corrected: Pass only the object to be shared
    }



    /// Withdraw funds from the bank.
    public entry fun withdraw_fees(
        bank: &mut Bank,
        admin_cap: &AdminCap,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Ensure the caller is the admin
        let caller = tx_context::sender(ctx);
        assert!(caller == bank.admin, E_NOT_AUTHORIZED);

        // Split the amount from the bank's balance
        let withdrawn = coin::split(&mut bank.balance, amount, ctx);

        // Transfer the withdrawn coins to the admin
        transfer::public_transfer(withdrawn, caller);
    }

    /// Send a message with an optional NFT attachment to the recipient’s mailbox.
public entry fun send_message_with_nft(
    sender_mailbox: &mut Mailbox,
    recipient_mailbox: &Mailbox,
    bank: &mut Bank, // Bank object to collect fees
    payment: &mut Coin<u64>,
    cid: vector<u8>,
    nft_object_id: option::Option<address>,
    claim_price: option::Option<u64>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender_addr = tx_context::sender(ctx);
    let timestamp = clock::timestamp_ms(clock);

    // Deduct fee and add to the bank
    let fee_payment: Coin<u64> = coin::split(payment, MESSAGE_FEE, ctx);
    coin::join(&mut bank.balance, fee_payment); // Bank must be mutable to modify balance

    let id = vector::length(&recipient_mailbox.messages) as u64 + 1;

    let message = MessageWithNFT {
        id,
        sender: sender_addr,
        receiver: recipient_mailbox.owner,
        cid,
        timestamp,
        nft_object_id,
        claim_price,
    };

    vector::push_back(&mut sender_mailbox.messages, message); // Store message in sender's mailbox
}


    /// Claim an NFT from a message by paying the specified price.
    public entry fun claim_nft(
        mailbox: &mut Mailbox,
        message_id: u64,
        payment: Coin<u64>,
        ctx: &mut TxContext
    ) {
        assert!(message_id < vector::length(&mailbox.messages) as u64, E_ITEM_NOT_FOUND); // Ensure the message exists
        let mut message = vector::borrow_mut(&mut mailbox.messages, message_id);

        // Ensure the message has an attached NFT and a claim price
        assert!(option::is_some(&message.nft_object_id), E_NO_NFT_ATTACHED);
        assert!(option::is_some(&message.claim_price), E_NO_CLAIM_PRICE);

        let price = option::get_with_default(&message.claim_price, 0);
        let coin_balance = coin::value(&payment);

        // Ensure the payment is sufficient
        assert!(coin_balance >= price, E_INSUFFICIENT_FUNDS);

        // Transfer the payment to the sender of the message
        transfer::public_transfer(payment, message.sender);

        // Reset the NFT and claim price fields
        message.nft_object_id = option::none();
        message.claim_price = option::none();
    }

    /// Delete a message from the mailbox by its ID.
    public entry fun delete_message(
        mailbox: &mut Mailbox,
        message_id: u64,
        ctx: &mut TxContext
    ) {
        assert!(message_id < vector::length(&mailbox.messages) as u64, E_ITEM_NOT_FOUND); // Ensure the message exists
        vector::remove(&mut mailbox.messages, message_id); // Remove the message
    }

    /// Get the number of messages in the mailbox.
    public fun get_mailbox_length(mailbox: &Mailbox): u64 {
        vector::length(&mailbox.messages)
    }

    /// Delete the entire mailbox.
    public entry fun delete_mailbox(
        mailbox: Mailbox,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx); // Get the sender's address
        assert!(owner == mailbox.owner, E_NOT_AUTHORIZED); // Ensure only the owner can delete the mailbox

        // Destructure the mailbox to move the fields
        let Mailbox { id, messages: _, owner: _ } = mailbox;

        // Delete the mailbox by deleting its UID
        object::delete(id);
    }
}
