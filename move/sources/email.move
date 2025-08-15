module suimail::email {
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::vec_set::{Self, VecSet};
    use std::vector;
    use std::string::{Self, String};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_MAILBOX_EXISTS: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_MAILBOX_NOT_FOUND: u64 = 4;
    const E_EMAIL_NOT_FOUND: u64 = 5;
    const E_INVALID_EMAIL_ADDRESS: u64 = 6;
    const E_ATTACHMENT_LIMIT_EXCEEDED: u64 = 7;
    const E_EMAIL_SIZE_LIMIT_EXCEEDED: u64 = 8;

    /// Configuration constants
    const MAILBOX_CREATION_FEE: u64 = 500_000_000; // 0.5 SUI
    const EMAIL_SEND_FEE: u64 = 25_000_000;        // 0.025 SUI
    const MAX_ATTACHMENTS_PER_EMAIL: u64 = 10;
    const MAX_EMAIL_SIZE_BYTES: u64 = 10_000_000;  // 10MB

    /// Email status enum
    public struct EmailStatus has copy, drop {
        is_read: bool,
        is_starred: bool,
        is_deleted: bool,
        is_archived: bool,
    }

    /// Email attachment
    public struct EmailAttachment has store {
        filename: String,
        content_type: String,
        walrus_cid: vector<u8>,  // Content ID in Walrus storage
        size_bytes: u64,
        encryption_key: vector<u8>, // Encrypted key for the attachment
    }

    /// Email message with full email functionality
    public struct Email has store {
        id: UID,
        sender: address,
        sender_address: String,  // Human-readable sender address (e.g., "user.sui")
        recipients: vector<address>,
        recipient_addresses: vector<String>, // Human-readable recipient addresses
        subject: String,
        body_cid: vector<u8>,    // Content ID for email body in Walrus
        body_encryption_key: vector<u8>,
        attachments: vector<EmailAttachment>,
        timestamp: u64,
        thread_id: vector<u8>,   // For email threading/replies
        parent_email_id: Option<UID>, // For reply chains
        status: EmailStatus,
        priority: u8,            // 0=normal, 1=high, 2=urgent
    }

    /// Mailbox for storing user emails
    public struct Mailbox has key, store {
        id: UID,
        owner: address,
        owner_address: String,   // Human-readable owner address
        emails: vector<Email>,
        folders: Table<String, vector<UID>>, // Custom folders
        contacts: VecSet<address>, // Address book
        settings: EmailSettings,
    }

    /// Email settings for user preferences
    public struct EmailSettings has store {
        auto_archive: bool,
        auto_delete_days: u64,
        signature: String,
        theme: String,
        notifications_enabled: bool,
    }

    /// Central registry for managing mailboxes and collecting fees
    public struct EmailRegistry has key {
        id: UID,
        owner: address,
        owner_to_mailbox: Table<address, Mailbox>,
        fee_balance: Balance<SUI>,
        mailbox_creation_fee: u64,
        email_send_fee: u64,
        total_emails_sent: u64,
        total_users: u64,
    }

    /// Events
    public struct EmailSent has copy, drop {
        sender: address,
        recipients: vector<address>,
        subject: String,
        timestamp: u64,
        thread_id: vector<u8>,
    }

    public struct MailboxCreated has copy, drop {
        owner: address,
        owner_address: String,
        timestamp: u64,
    }

    public struct EmailStatusChanged has copy, drop {
        email_id: UID,
        owner: address,
        new_status: EmailStatus,
        timestamp: u64,
    }

    /// Initialize the email module
    fun init(ctx: &mut TxContext) {
        let deployer = tx_context::sender(ctx);
        transfer::share_object(EmailRegistry {
            id: object::new(ctx),
            owner: deployer,
            owner_to_mailbox: table::new(ctx),
            fee_balance: balance::zero<SUI>(),
            mailbox_creation_fee: MAILBOX_CREATION_FEE,
            email_send_fee: EMAIL_SEND_FEE,
            total_emails_sent: 0,
            total_users: 0,
        });
    }

    /// Create a mailbox for a user
    public entry fun create_mailbox(
        registry: &mut EmailRegistry,
        payment: Coin<SUI>,
        owner_address: String,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(!table::contains(&registry.owner_to_mailbox, sender), E_MAILBOX_EXISTS);
        assert!(coin::value(&payment) == registry.mailbox_creation_fee, E_INSUFFICIENT_FUNDS);
        
        balance::join(&mut registry.fee_balance, coin::into_balance(payment));
        
        let default_folders = vector::empty<String>();
        let inbox = string::utf8(b"Inbox");
        let sent = string::utf8(b"Sent");
        let drafts = string::utf8(b"Drafts");
        let trash = string::utf8(b"Trash");
        let archive = string::utf8(b"Archive");
        
        vector::push_back(&mut default_folders, inbox);
        vector::push_back(&mut default_folders, sent);
        vector::push_back(&mut default_folders, drafts);
        vector::push_back(&mut default_folders, trash);
        vector::push_back(&mut default_folders, archive);

        let mailbox = Mailbox {
            id: object::new(ctx),
            owner: sender,
            owner_address,
            emails: vector::empty<Email>(),
            folders: table::new(ctx),
            contacts: vec_set::empty(),
            settings: EmailSettings {
                auto_archive: false,
                auto_delete_days: 30,
                signature: string::utf8(b""),
                theme: string::utf8(b"light"),
                notifications_enabled: true,
            },
        };

        // Initialize default folders
        let mut i = 0;
        while (i < vector::length(&default_folders)) {
            let folder_name = *vector::borrow(&default_folders, i);
            table::add(&mut mailbox.folders, folder_name, vector::empty<UID>());
            i = i + 1;
        };

        table::add(&mut registry.owner_to_mailbox, sender, mailbox);
        registry.total_users = registry.total_users + 1;

        event::emit(MailboxCreated {
            owner: sender,
            owner_address,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Send an email
    public entry fun send_email(
        registry: &mut EmailRegistry,
        payment: Coin<SUI>,
        recipients: vector<address>,
        recipient_addresses: vector<String>,
        subject: String,
        body_cid: vector<u8>,
        body_encryption_key: vector<u8>,
        attachments: vector<EmailAttachment>,
        thread_id: vector<u8>,
        parent_email_id: Option<UID>,
        priority: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let timestamp = clock::timestamp_ms(clock);

        // Validate inputs
        assert!(coin::value(&payment) == registry.email_send_fee, E_INSUFFICIENT_FUNDS);
        assert!(vector::length(&recipients) == vector::length(&recipient_addresses), E_INVALID_EMAIL_ADDRESS);
        assert!(vector::length(&attachments) <= MAX_ATTACHMENTS_PER_EMAIL, E_ATTACHMENT_LIMIT_EXCEEDED);
        
        // Check if sender has mailbox
        assert!(table::contains(&registry.owner_to_mailbox, sender), E_MAILBOX_NOT_FOUND);
        
        // Check if all recipients have mailboxes
        let mut i = 0;
        while (i < vector::length(&recipients)) {
            let recipient = *vector::borrow(&recipients, i);
            assert!(table::contains(&registry.owner_to_mailbox, recipient), E_MAILBOX_NOT_FOUND);
            i = i + 1;
        };

        balance::join(&mut registry.fee_balance, coin::into_balance(payment));

        // Create email object
        let email = Email {
            id: object::new(ctx),
            sender,
            sender_address: get_user_address(registry, sender),
            recipients,
            recipient_addresses,
            subject,
            body_cid,
            body_encryption_key,
            attachments,
            timestamp,
            thread_id,
            parent_email_id,
            status: EmailStatus {
                is_read: false,
                is_starred: false,
                is_deleted: false,
                is_archived: false,
            },
            priority,
        };

        // Add to sender's sent folder
        let sender_mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, sender);
        vector::push_back(&mut sender_mailbox.emails, email);

        // Add to each recipient's inbox
        let mut i = 0;
        while (i < vector::length(&recipients)) {
            let recipient = *vector::borrow(&recipients, i);
            let recipient_mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, recipient);
            
            let recipient_email = Email {
                id: object::new(ctx),
                sender,
                sender_address: get_user_address(registry, sender),
                recipients,
                recipient_addresses,
                subject,
                body_cid,
                body_encryption_key,
                attachments,
                timestamp,
                thread_id,
                parent_email_id,
                status: EmailStatus {
                    is_read: false,
                    is_starred: false,
                    is_deleted: false,
                    is_archived: false,
                },
                priority,
            };
            
            vector::push_back(&mut recipient_mailbox.emails, recipient_email);
            i = i + 1;
        };

        registry.total_emails_sent = registry.total_emails_sent + 1;

        event::emit(EmailSent {
            sender,
            recipients,
            subject,
            timestamp,
            thread_id,
        });
    }

    /// Mark email as read/unread
    public entry fun mark_email_read(
        registry: &mut EmailRegistry,
        email_index: u64,
        is_read: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        assert!(email_index < vector::length(&mailbox.emails), E_EMAIL_NOT_FOUND);
        
        let email = vector::borrow_mut(&mut mailbox.emails, email_index);
        email.status.is_read = is_read;

        event::emit(EmailStatusChanged {
            email_id: object::id(email),
            owner: caller,
            new_status: *&email.status,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Star/unstar an email
    public entry fun toggle_email_star(
        registry: &mut EmailRegistry,
        email_index: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        assert!(email_index < vector::length(&mailbox.emails), E_EMAIL_NOT_FOUND);
        
        let email = vector::borrow_mut(&mut mailbox.emails, email_index);
        email.status.is_starred = !email.status.is_starred;

        event::emit(EmailStatusChanged {
            email_id: object::id(email),
            owner: caller,
            new_status: *&email.status,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Move email to trash
    public entry fun trash_email(
        registry: &mut EmailRegistry,
        email_index: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        assert!(email_index < vector::length(&mailbox.emails), E_EMAIL_NOT_FOUND);
        
        let email = vector::borrow_mut(&mut mailbox.emails, email_index);
        email.status.is_deleted = true;

        event::emit(EmailStatusChanged {
            email_id: object::id(email),
            owner: caller,
            new_status: *&email.status,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Archive an email
    public entry fun archive_email(
        registry: &mut EmailRegistry,
        email_index: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        assert!(email_index < vector::length(&mailbox.emails), E_EMAIL_NOT_FOUND);
        
        let email = vector::borrow_mut(&mut mailbox.emails, email_index);
        email.status.is_archived = true;

        event::emit(EmailStatusChanged {
            email_id: object::id(email),
            owner: caller,
            new_status: *&email.status,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Add contact to address book
    public entry fun add_contact(
        registry: &mut EmailRegistry,
        contact_address: address,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        vec_set::insert(&mut mailbox.contacts, contact_address);
    }

    /// Remove contact from address book
    public entry fun remove_contact(
        registry: &mut EmailRegistry,
        contact_address: address,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        vec_set::remove(&mut mailbox.contacts, &contact_address);
    }

    /// Update email settings
    public entry fun update_email_settings(
        registry: &mut EmailRegistry,
        auto_archive: bool,
        auto_delete_days: u64,
        signature: String,
        theme: String,
        notifications_enabled: bool,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(table::contains(&registry.owner_to_mailbox, caller), E_MAILBOX_NOT_FOUND);
        
        let mailbox = table::borrow_mut(&mut registry.owner_to_mailbox, caller);
        mailbox.settings.auto_archive = auto_archive;
        mailbox.settings.auto_delete_days = auto_delete_days;
        mailbox.settings.signature = signature;
        mailbox.settings.theme = theme;
        mailbox.settings.notifications_enabled = notifications_enabled;
    }

    /// Helper function to get user's readable address
    fun get_user_address(registry: &EmailRegistry, user: address): String {
        if (table::contains(&registry.owner_to_mailbox, user)) {
            let mailbox = table::borrow(&registry.owner_to_mailbox, user);
            mailbox.owner_address
        } else {
            string::utf8(b"unknown.sui")
        }
    }

    /// Collect accumulated fees (admin only)
    public entry fun collect_fees(
        registry: &mut EmailRegistry,
        ctx: &mut TxContext
    ) {
        let deployer = tx_context::sender(ctx);
        assert!(deployer == registry.owner, E_NOT_AUTHORIZED);
        let amount = balance::value(&registry.fee_balance);
        let fees = coin::take(&mut registry.fee_balance, amount, ctx);
        transfer::public_transfer(fees, deployer);
    }

    /// Update fees (admin only)
    public entry fun set_mailbox_creation_fee(
        registry: &mut EmailRegistry,
        new_fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.owner, E_NOT_AUTHORIZED);
        registry.mailbox_creation_fee = new_fee;
    }

    public entry fun set_email_send_fee(
        registry: &mut EmailRegistry,
        new_fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.owner, E_NOT_AUTHORIZED);
        registry.email_send_fee = new_fee;
    }

    /// Get mailbox statistics
    public fun get_mailbox_stats(registry: &EmailRegistry, user: address): (u64, u64, u64) {
        if (table::contains(&registry.owner_to_mailbox, user)) {
            let mailbox = table::borrow(&registry.owner_to_mailbox, user);
            let total_emails = vector::length(&mailbox.emails);
            let unread_count = 0; // TODO: Implement unread counting
            let starred_count = 0; // TODO: Implement starred counting
            (total_emails, unread_count, starred_count)
        } else {
            (0, 0, 0)
        }
    }

    /// Get registry statistics
    public fun get_registry_stats(registry: &EmailRegistry): (u64, u64, u64) {
        (registry.total_users, registry.total_emails_sent, balance::value(&registry.fee_balance))
    }
}