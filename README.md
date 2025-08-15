# SuiMail v2: Decentralized Email System

SuiMail is a completely decentralized email system built on the Sui blockchain using Walrus Protocol for storage and Walrus sites for the frontend. This represents a complete overhaul from the previous chat/NFT marketplace system to focus purely on decentralized email functionality.

## 🚀 What's New in v2

- **Pure Email Focus**: Removed NFT/store functionality to focus on email
- **Walrus Protocol Integration**: All email content stored in decentralized storage
- **SuiNS Integration**: Human-readable email addresses (e.g., "alice.sui")
- **Modern Email Features**: Subjects, attachments, threading, folders, contacts
- **Walrus Site Frontend**: Beautiful, responsive web interface
- **Enhanced Security**: End-to-end encryption with blockchain verification

## 🏗️ Architecture

### Smart Contracts (Move)
- **`email.move`**: Core email functionality with Walrus integration
- **`suins_integration.move`**: SuiNS domain management for human-readable addresses
- **`walrus_integration.move`**: Decentralized storage management via Walrus Protocol
- **`profile_v2.move`**: Simplified user profiles focused on email functionality
- **`admin.move`**: Administrative functions

### Frontend (Walrus Site)
- **Modern UI/UX**: Professional email interface design
- **Responsive Design**: Works on all devices
- **Wallet Integration**: Seamless Sui wallet connection
- **Interactive Demo**: Live email interface preview

## 🔧 Key Features

### Email System
- ✅ Create decentralized mailboxes
- ✅ Send/receive encrypted emails
- ✅ Email threading and replies
- ✅ File attachments (up to 10 per email)
- ✅ Email status management (read, starred, archived, deleted)
- ✅ Custom folders and organization
- ✅ Contact management
- ✅ Email signatures and themes

### Decentralized Storage
- ✅ Walrus Protocol integration
- ✅ Content addressing (CIDs)
- ✅ Encrypted storage
- ✅ Automatic retention policies
- ✅ Storage allocation management

### User Experience
- ✅ Human-readable addresses via SuiNS
- ✅ Familiar email interface
- ✅ Real-time notifications
- ✅ Cross-platform compatibility
- ✅ Offline capability

## 🚀 Getting Started

### Prerequisites
- Sui wallet (Suiet, Sui Wallet Extension, or Martian)
- Sui testnet/mainnet access

### 1. Deploy Smart Contracts
```bash
cd move
sui move build
sui client publish --gas-budget 100000000
```

### 2. Deploy Walrus Site
```bash
cd walrus-site
# Deploy to your preferred hosting service or Walrus Protocol
```

### 3. Create Your Mailbox
1. Connect your Sui wallet
2. Pay the mailbox creation fee (0.5 SUI)
3. Choose your SuiNS address (e.g., "yourname.sui")
4. Start sending emails!

## 📱 Usage

### Creating a Mailbox
```move
// Create mailbox with SuiNS address
create_mailbox(
    registry: &mut EmailRegistry,
    payment: Coin<SUI>, // 0.5 SUI
    owner_address: "alice.sui",
    ctx: &mut TxContext
)
```

### Sending an Email
```move
// Send email with attachments
send_email(
    registry: &mut EmailRegistry,
    payment: Coin<SUI>, // 0.025 SUI
    recipients: [recipient_address],
    recipient_addresses: ["bob.sui"],
    subject: "Hello from SuiMail!",
    body_cid: walrus_cid,
    body_encryption_key: encrypted_key,
    attachments: [attachment_data],
    thread_id: thread_identifier,
    parent_email_id: None,
    priority: 0, // 0=normal, 1=high, 2=urgent
    clock: &Clock,
    ctx: &mut TxContext
)
```

### Managing Storage
```move
// Allocate storage for emails and attachments
allocate_storage(
    registry: &mut WalrusRegistry,
    allocated_bytes: 1_000_000_000, // 1GB
    max_file_size: 10_000_000, // 10MB max per file
    retention_days: 365,
    ctx: &mut TxContext
)
```

## 🔐 Security Features

- **End-to-End Encryption**: All email content encrypted before storage
- **Blockchain Verification**: Email metadata stored on-chain for immutability
- **Decentralized Storage**: No single point of failure
- **User Control**: Users own their encryption keys
- **Audit Trail**: All email activities recorded on blockchain

## 🌐 Walrus Protocol Integration

SuiMail leverages Walrus Protocol for decentralized storage:

- **Content Addressing**: Each email gets a unique CID
- **Distributed Storage**: Content spread across multiple nodes
- **Automatic Replication**: Built-in redundancy and availability
- **Cost-Effective**: Pay only for storage used
- **Global Access**: Access emails from anywhere in the world

## 👤 SuiNS Integration

Human-readable email addresses via SuiNS:

- **Easy to Remember**: "alice.sui" instead of "0x1234...abcd"
- **Professional**: Use your brand or personal name
- **Portable**: Keep your address even if you change wallets
- **Verified**: Domain verification system for security

## 💰 Fee Structure

- **Mailbox Creation**: 0.5 SUI (one-time)
- **Email Sending**: 0.025 SUI per email
- **Storage**: 1 SUI per GB per month
- **SuiNS Registration**: Varies by domain

## 🛠️ Development

### Smart Contract Development
```bash
cd move
sui move test # Run tests
sui move build # Build contracts
sui move publish # Deploy to network
```

### Frontend Development
```bash
cd walrus-site
# Edit HTML, CSS, JavaScript files
# Test locally with a web server
```

### Testing
```bash
cd move
sui move test
```

## 📊 Performance

- **Email Delivery**: Near-instant via Sui blockchain
- **Storage Retrieval**: Fast access via Walrus Protocol
- **Scalability**: Handles millions of users
- **Cost Efficiency**: Minimal gas fees for operations

## 🔮 Roadmap

### Phase 1 (Current)
- ✅ Core email functionality
- ✅ Walrus Protocol integration
- ✅ SuiNS integration
- ✅ Basic email interface

### Phase 2 (Next)
- 🔄 Advanced email features (filters, rules, auto-replies)
- 🔄 Mobile applications
- 🔄 API for third-party integrations
- 🔄 Enhanced security features

### Phase 3 (Future)
- 🔄 Cross-chain email support
- 🔄 Advanced AI features
- 🔄 Enterprise features
- 🔄 Global email federation

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs.suimail.sui](https://docs.suimail.sui)
- **Discord**: [discord.gg/suimail](https://discord.gg/suimail)
- **Twitter**: [@SuiMail](https://twitter.com/SuiMail)
- **Email**: support@suimail.sui

## 🙏 Acknowledgments

- **Sui Foundation**: For the high-performance blockchain
- **Walrus Protocol**: For decentralized storage solutions
- **SuiNS Team**: For human-readable addressing
- **Community**: For feedback and contributions

---

**SuiMail v2**: The future of decentralized email is here! 🚀📧
