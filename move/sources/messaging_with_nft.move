module suimail::messaging {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::vector;
    use std::option::{Self, Option, some, none, is_some, borrow};
    use suimail::admin::{Self, Bank}; // ✅ Use the Bank from admin module

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ITEM_NOT_FOUND: u64 = 2;

    /// Hardcoded Fee Variables
    const MESSAGE_FEE: u64 = 100_000_000; // 0.1 SUI fee

    /// ✅ Structs with `key` must have `UID` as the first field
    public struct MessageWithNFT has store, key {
        id: UID,  // ✅ Correctly using `UID`
        sender: address,
        receiver: address,
        cid: vector<u8>,  // Content ID for off-chain storage
        timestamp: u64,
        nft_object_id: Option<address>, // ✅ Optional NFT
        claim_price: Option<u64>,       // ✅ Optional claim price in SUI
    }

    public struct Message has store, key {
        id: UID,  // ✅ Correctly using `UID`
        sender: address,
        receiver: address,
        cid: vector<u8>,  // Content ID for off-chain storage
        timestamp: u64,
    }

    public struct Mailbox has store, key {
        id: UID,
        owner: address,
        messages: vector<u64>, // Store only message numeric IDs
        next_message_id: u64,  // Auto-incrementing ID counter
    }

    public struct AdminCap has store, key {
        id: UID,
    }

    /// ✅ Convert an `ID` to `u64` safely
    fun id_to_numeric(id: &ID): u64 {
    let bytes = object::id_to_bytes(id); // ✅ Remove `*id`, since `id` is already a reference
    (bytes[0] as u64) | ((bytes[1] as u64) << 8) | ((bytes[2] as u64) << 16) | ((bytes[3] as u64) << 24) |
    ((bytes[4] as u64) << 32) | ((bytes[5] as u64) << 40) | ((bytes[6] as u64) << 48) | ((bytes[7] as u64) << 56)
}

    /// ✅ Initialize a new mailbox
    public entry fun init_mailbox(ctx: &mut TxContext) {
        let mailbox = Mailbox {
            id: object::new(ctx),  // ✅ Correctly initializes a `UID`
            owner: tx_context::sender(ctx),
            messages: vector::empty<u64>(),
            next_message_id: 0,
        };
        transfer::transfer(mailbox, tx_context::sender(ctx)); // ✅ Transfer ownership to sender
    }

    public entry fun send_message_with_nft(
    sender_mailbox: &mut Mailbox,
    recipient_mailbox: &mut Mailbox,
    bank: &mut Bank, // ✅ Use shared Bank from admin module
    payment: &mut Coin<u64>,
    cid: vector<u8>, // Message content CID
    nft_object_id: Option<address>, // ✅ Optional NFT
    claim_price: Option<u64>, // ✅ Optional claim price in SUI
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender_addr = tx_context::sender(ctx);
    let timestamp = clock::timestamp_ms(clock);
    let fee_payment = coin::split(payment, MESSAGE_FEE, ctx);

    // ✅ Deposit 0.1 SUI fees into the bank
    suimail::admin::deposit_fees(bank, fee_payment);

    let message = MessageWithNFT {
        id: object::new(ctx), // ✅ Generates a `UID`
        sender: sender_addr,
        receiver: recipient_mailbox.owner,
        cid,
        timestamp,
        nft_object_id,
        claim_price,
    };

    // ✅ Store the message first
    transfer::public_share_object(message);

    // ✅ Extract `ID` from stored `UID`
    let message_id = object::id(&message); // Extract ID from object
    let message_numeric_id = id_to_numeric(&message_id); // Convert ID to u64


    // ✅ Store only the numeric representation in mailbox
    vector::push_back(&mut recipient_mailbox.messages, message_numeric_id);
}

    /// ✅ Delete a message reference from the mailbox (message remains on-chain)
    public entry fun delete_message(mailbox: &mut Mailbox, message_id: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(sender == mailbox.owner, E_NOT_AUTHORIZED);

        let (found, index) = vector::index_of(&mailbox.messages, &message_id);
        assert!(found, E_ITEM_NOT_FOUND);

        vector::remove(&mut mailbox.messages, index);
    }

    /// ✅ Get the number of messages in the mailbox
    public fun get_mailbox_length(mailbox: &Mailbox): u64 {
        vector::length(&mailbox.messages)
    }

    /// ✅ Delete the entire mailbox
    public entry fun delete_mailbox(mailbox: Mailbox, ctx: &mut TxContext) {
        let owner = tx_context::sender(ctx);
        assert!(owner == mailbox.owner, E_NOT_AUTHORIZED);
        let Mailbox { id, messages: _, owner: _, next_message_id: _ } = mailbox;
        object::delete(id);
    }

    /// ✅ Get all message IDs stored in a mailbox
    public fun get_all_messages(mailbox: &Mailbox): vector<u64> {
        mailbox.messages
    }
}


