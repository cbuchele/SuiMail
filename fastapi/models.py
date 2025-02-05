from sqlalchemy import create_engine, Column, Integer, String, ForeignKey, BigInteger, Text, Table
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship

# Database setup
DATABASE_URL = "mysql+pymysql://root:Pl.ystation5!@localhost/suimail"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 👤 User Model
class User(Base):
    __tablename__ = "users"
    wallet_address = Column(String(200), primary_key=True, index=True)
    username = Column(String(60))
    display_name = Column(String(12))
    bio = Column(String(200))
    avatar_cid = Column(String(200))
    
    # One-to-One: Each User has One Mailbox
    mailbox = relationship("Mailbox", back_populates="owner", uselist=False)

# 📬 Mailbox Model (Each user has a mailbox)
class Mailbox(Base):
    __tablename__ = "mailboxes"
    id = Column(Integer, primary_key=True, index=True)
    mailbox_id = Column(String(120), unique=True, index=True)
    owner_wallet = Column(String(200), ForeignKey("users.wallet_address"), unique=True)  # One-to-One with User
    owner = relationship("User", back_populates="mailbox")

    # One-to-Many: A Mailbox stores multiple MessagesWithNFT and Messages
    messages_with_nft = relationship("MessageWithNFT", back_populates="mailbox")
    messages = relationship("Message", back_populates="mailbox")

# ✉️ MessageWithNFT Model (Stored inside a Mailbox)
class MessageWithNFT(Base):
    __tablename__ = "messages_with_nft"
    id = Column(BigInteger, primary_key=True, index=True)  # ✅ u64 in Sui = BigInteger in SQL
    sender = Column(String(200))  # ✅ Address
    receiver = Column(String(200))  # ✅ Address
    cid = Column(Text)  # ✅ Content ID (stored as bytes in Move, stored as text in SQL)
    timestamp = Column(BigInteger)  # ✅ u64 timestamp
    nft_object_id = Column(String(200), nullable=True)  # ✅ Option<address> = Nullable String
    claim_price = Column(BigInteger, nullable=True)  # ✅ Option<u64> = Nullable Integer

    mailbox_id = Column(String(120), ForeignKey("mailboxes.mailbox_id"))  # ✅ Message belongs to a mailbox
    mailbox = relationship("Mailbox", back_populates="messages_with_nft")

# ✉️ Message Model (Simple message without NFT)
class Message(Base):
    __tablename__ = "messages"
    id = Column(BigInteger, primary_key=True, index=True)  # ✅ u64 in Sui = BigInteger in SQL
    sender = Column(String(200))  # ✅ Address
    receiver = Column(String(200))  # ✅ Address
    cid = Column(Text)  # ✅ Content ID (stored as bytes in Move, stored as text in SQL)
    timestamp = Column(BigInteger)  # ✅ u64 timestamp

    mailbox_id = Column(String(120), ForeignKey("mailboxes.mailbox_id"))  # ✅ Message belongs to a mailbox
    mailbox = relationship("Mailbox", back_populates="messages")

# 🏪 MailboxRegistry Model (Maps user addresses to their mailboxes)
class MailboxRegistry(Base):
    __tablename__ = "mailbox_registry"
    id = Column(Integer, primary_key=True, index=True)
    owner_wallet = Column(String(200), ForeignKey("users.wallet_address"), unique=True)  # One-to-One with User
    mailbox_id = Column(String(120), ForeignKey("mailboxes.mailbox_id"))  # One-to-One with Mailbox

    # Relationships
    owner = relationship("User", back_populates="mailbox_registry")
    mailbox = relationship("Mailbox", back_populates="registry")

# 🏪 Kiosk Model
class Kiosk(Base):
    __tablename__ = "kiosks"
    id = Column(Integer, primary_key=True, index=True)
    kiosk_id = Column(String(120), unique=True, index=True)
    owner_wallet = Column(String(200), ForeignKey("users.wallet_address"))
    items = relationship("KioskItem", back_populates="kiosk")

# 🛒 Kiosk Item Model
class KioskItem(Base):
    __tablename__ = "kiosk_items"
    id = Column(Integer, primary_key=True, index=True)
    item_id = Column(String(120), unique=True, index=True)
    kiosk_id = Column(String(120), ForeignKey("kiosks.kiosk_id"))
    title = Column(String(200))
    content_cid = Column(String(200))
    price = Column(BigInteger)  # ✅ Storing as BigInteger to match Sui u64
    kiosk = relationship("Kiosk", back_populates="items")

# Update User Model to include MailboxRegistry relationship
User.mailbox_registry = relationship("MailboxRegistry", back_populates="owner", uselist=False)

# Update Mailbox Model to include MailboxRegistry relationship
Mailbox.registry = relationship("MailboxRegistry", back_populates="mailbox", uselist=False)

# Create tables in the database
Base.metadata.create_all(bind=engine)