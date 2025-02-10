from sqlalchemy import create_engine, Column, Integer, String, ForeignKey, BigInteger, Text
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
    address = Column(String(200), primary_key=True, index=True)
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
    owner_wallet = Column(String(200), ForeignKey("users.address"), unique=True)  # One-to-One with User
    owner = relationship("User", back_populates="mailbox")

    # One-to-Many: A Mailbox stores multiple MessagesWithNFT
    messages = relationship("MessageWithNFT", back_populates="mailbox")

# ✉️ MessageWithNFT Model (Stored inside a Mailbox)
class MessageWithNFT(Base):
    __tablename__ = "messages_with_nft"
    id = Column(BigInteger, primary_key=True, index=True)
    sender = Column(String(200))
    receiver = Column(String(200))
    cid = Column(Text)  # CID for IPFS reference
    content = Column(Text)  # Actual message content (-store this as well)
    timestamp = Column(BigInteger)
    nft_object_id = Column(String(200), nullable=True)
    claim_price = Column(BigInteger, nullable=True)
    mailbox_id = Column(String(120), ForeignKey("mailboxes.mailbox_id"))
    mailbox = relationship("Mailbox", back_populates="messages")

# 🏪 Kiosk Model
class Kiosk(Base):
    __tablename__ = "kiosks"
    id = Column(Integer, primary_key=True, index=True)
    kiosk_id = Column(String(120), unique=True, index=True)
    owner_wallet = Column(String(200), ForeignKey("users.address"))
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

# Create tables in the database
Base.metadata.create_all(bind=engine)
