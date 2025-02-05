module suimail::messaging {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use sui::table::{Self, Table};

    use std::vector;
    use std::option::{Self, Option, some, none, is_some, borrow};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ITEM_NOT_FOUND: u64 = 2;
    const E_MAILBOX_EXISTS: u64 = 3;
    const E_INSUFFICIENT_FUNDS: u64 = 4;

    /// Hardcoded Fee Variables
    const MESSAGE_FEE: u64 = 100_000_000; // 0.1 SUI fee

    /// Message with optional NFT attachment
    public struct MessageWithNFT has store, key {
        id: UID,
        sender: address,
        receiver: address,
        cid: vector<u8>,  // Content ID for off-chain storage (IPFS or Walrus)
        timestamp: u64,
        nft_object_id: Option<address>, // Optional NFT
        claim_price: Option<u64>,       // Optional claim price in SUI
    }

    /// Simple message without NFT
    public struct Message has store, key {
        id: UID,
        sender: address,
        receiver: address,
        cid: vector<u8>,  // Content ID for off-chain storage
        timestamp: u64,
    }

    /// Mailbox for a user
    public struct Mailbox has store, key {
        id: UID,
        owner: address, // ✅ Add owner field
        messages: vector<u64>, // Stores message IDs
        next_message_id: u64,  // Auto-incrementing ID counter
    }

    /// Registry to map user addresses to their mailboxes
    public struct MailboxRegistry has key {
        id: UID,
        owner_to_mailbox: Table<address, Mailbox>, // Maps owner address to their mailbox
    }

    /// Admin capability for privileged actions
    public struct AdminCap has key {
        id: UID,
    }

    /// Convert an `ID` to `u64` safely
    fun id_to_numeric(id: &ID): u64 {
        let bytes = object::id_to_bytes(id);
        (bytes[0] as u64) | ((bytes[1] as u64) << 8) | ((bytes[2] as u64) << 16) | ((bytes[3] as u64) << 24) |
        ((bytes[4] as u64) << 32) | ((bytes[5] as u64) << 40) | ((bytes[6] as u64) << 48) | ((bytes[7] as u64) << 56)
    }

    /// Initialize the mailbox registry
    fun init(ctx: &mut TxContext) {
        // Initialize the MailboxRegistry
        let registry = MailboxRegistry {
            id: object::new(ctx),
            owner_to_mailbox: table::new(ctx),
        };

        // Share the registry object to make it globally accessible
        transfer::share_object(registry);
    }

    /// Create a mailbox for a user
    public entry fun create_mailbox(registry: &mut MailboxRegistry, ctx: &mut TxContext) {
        let owner = tx_context::sender(ctx);
        assert!(!table::contains(&registry.owner_to_mailbox, owner), E_MAILBOX_EXISTS);

        let mailbox = Mailbox {
            id: object::new(ctx),
            owner, // ✅ Set the owner field
            messages: vector::empty<u64>(),
            next_message_id: 0,
        };
        table::add(&mut registry.owner_to_mailbox, owner, mailbox);
    }

    /// Send a message with optional NFT attachment
    public entry fun send_message_with_nft(
        registry: &mut MailboxRegistry,
        payment: &mut Coin<SUI>,
        cid: vector<u8>, // IPFS or Walrus content ID
        nft_object_id: Option<address>,
        claim_price: Option<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let recipient_mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, sender);

        // Ensure the sender has enough funds to pay the fee
        assert!(coin::value(payment) >= MESSAGE_FEE, E_INSUFFICIENT_FUNDS);

        // Deduct the fee from the payment
        let fee_payment = coin::split(payment, MESSAGE_FEE, ctx);

        // Transfer the fee to the recipient's mailbox using public_transfer
        transfer::public_transfer(fee_payment, recipient_mailbox.owner);

        let message = MessageWithNFT {
            id: object::new(ctx),
            sender,
            receiver: recipient_mailbox.owner,
            cid,
            timestamp: clock::timestamp_ms(clock),
            nft_object_id,
            claim_price,
        };

        let message_id = object::id(&message);
        transfer::public_share_object(message);
        let message_numeric_id = id_to_numeric(&message_id);

        vector::push_back(&mut recipient_mailbox.messages, message_numeric_id);
    }

    /// Delete a message from a mailbox
    public entry fun delete_message(
        registry: &mut MailboxRegistry,
        message_id: u64,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, owner);

        let (found, index) = vector::index_of(&mailbox.messages, &message_id);
        assert!(found, E_ITEM_NOT_FOUND);

        vector::remove(&mut mailbox.messages, index);
    }

    /// Get all message IDs in a mailbox
    public fun get_messages(registry: &MailboxRegistry, owner: address): vector<u64> {
        let mailbox = table::borrow(&registry.owner_to_mailbox, owner);
        mailbox.messages
    }

    /// Get the number of messages in a mailbox
    public fun get_mailbox_length(registry: &MailboxRegistry, owner: address): u64 {
        let mailbox = table::borrow(&registry.owner_to_mailbox, owner);
        vector::length(&mailbox.messages)
    }
}