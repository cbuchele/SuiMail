module suimail::messaging {
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event; // Added for events

    use std::vector;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MAILBOX_EXISTS: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_MAILBOX_NOT_FOUND: u64 = 4;

    /// Hardcoded Fee Variables
    const MAILBOX_CREATION_FEE: u64 = 1_000_000_000; // 0.1 SUI fee for creating a mailbox
    const MESSAGE_SEND_FEE: u64 = 50_000_000;     // 0.05 SUI fee for sending a message

    /// Event emitted when a message is sent
    public struct SendMessage has copy, drop {
        sender: address,
        recipient: address,
        cid: vector<u8>,
        key: vector<u8>,
        timestamp: u64,
    }

    /// Mailbox for a user
    public struct Mailbox has key, store {
        id: UID,
        owner: address,
        messages: vector<Message>,
    }

    /// Message struct
    public struct Message has store {
        sender: address,
        cid: vector<u8>,  // Content ID for off-chain storage
        key: vector<u8>,  // Symmetric encryption key
        timestamp: u64,
    }

    /// Central registry for managing mailboxes and collecting fees
    public struct MailboxRegistry has key {
        id: UID,
        owner: address,
        owner_to_mailbox: Table<address, Mailbox>,
        fee_balance: Balance<SUI>,
        mailbox_creation_fee: u64,
        message_send_fee: u64,
    }

    /// Initialize the module
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        transfer::share_object(MailboxRegistry {
            id: object::new(ctx),
            owner: deployer,
            owner_to_mailbox: table::new(ctx),
            fee_balance: balance::zero<SUI>(),
            mailbox_creation_fee: MAILBOX_CREATION_FEE,
            message_send_fee: MESSAGE_SEND_FEE,
        });
    }

    /// Create a mailbox for a user (requires payment of the mailbox creation fee)
    public entry fun create_mailbox(
        registry: &mut MailboxRegistry,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(!table::contains(&registry.owner_to_mailbox, sender), E_MAILBOX_EXISTS);
        assert!(coin::value(&payment) == registry.mailbox_creation_fee, E_INSUFFICIENT_FUNDS);
        balance::join(&mut registry.fee_balance, coin::into_balance(payment));
        let mailbox = Mailbox {
            id: object::new(ctx),
            owner: sender,
            messages: vector::empty<Message>(),
        };
        table::add(&mut registry.owner_to_mailbox, sender, mailbox);
    }

    /// Send a message to a recipient (requires payment of the message send fee)
    public entry fun send_message(
        registry: &mut MailboxRegistry,
        payment: Coin<SUI>,
        recipient: address,
        cid: vector<u8>,
        key: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, recipient), E_MAILBOX_NOT_FOUND);
        assert!(coin::value(&payment) == registry.message_send_fee, E_INSUFFICIENT_FUNDS);
        balance::join(&mut registry.fee_balance, coin::into_balance(payment));

        let timestamp = clock::timestamp_ms(clock);
        let message = Message {
            sender,
            cid,
            key,
            timestamp,
        };

        // Emit the SendMessage event
        event::emit(SendMessage {
            sender,
            recipient,
            cid,
            key,
            timestamp,
        });

        let recipient_mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, recipient);
        vector::push_back(&mut recipient_mailbox.messages, message);
    }

    /// Collect accumulated fees (only callable by the deployer)
    public entry fun collect_fees(
        registry: &mut MailboxRegistry,
        ctx: &mut TxContext
    ) {
        let deployer = tx_context::sender(ctx);
        assert!(deployer == registry.owner, E_NOT_AUTHORIZED);
        let amount = balance::value(&registry.fee_balance);
        let fees = coin::take(&mut registry.fee_balance, amount, ctx);
        transfer::public_transfer(fees, deployer);
    }

    /// Update the mailbox creation fee (only callable by the deployer)
    public entry fun set_mailbox_creation_fee(
        registry: &mut MailboxRegistry,
        new_fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.owner, E_NOT_AUTHORIZED);
        registry.mailbox_creation_fee = new_fee;
    }

    /// Update the message send fee (only callable by the deployer)
    public entry fun set_message_send_fee(
        registry: &mut MailboxRegistry,
        new_fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.owner, E_NOT_AUTHORIZED);
        registry.message_send_fee = new_fee;
    }
}