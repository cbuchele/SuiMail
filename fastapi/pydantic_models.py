from pydantic import BaseModel
from typing import Optional, List

# 🛡️ Admin Models
class AdminCreate(BaseModel):
    username: str
    password: str

class AdminLogin(BaseModel):
    username: str
    password: str

# 👤 User Models
class UserCreate(BaseModel):
    wallet_address: str
    username: str
    display_name: str
    bio: str
    avatar_cid: str

class UserResponse(BaseModel):
    wallet_address: str
    username: str
    display_name: str
    bio: str
    avatar_cid: str
    mailbox_id: Optional[str] = None  # ✅ Link to the user's mailbox

# 📬 Mailbox Model (Each User has One Mailbox)
class MailboxCreate(BaseModel):
    mailbox_id: str
    owner_wallet: str

class MailboxResponse(BaseModel):
    mailbox_id: str
    owner_wallet: str
    messages: List["MessageResponse"] = []  # ✅ List of messages in the mailbox
    messages_with_nft: List["MessageWithNFTResponse"] = []  # ✅ List of messages with NFT

# ✉️ Message Model (Simple message without NFT)
class MessageCreate(BaseModel):
    sender: str
    receiver: str
    cid: str  # ✅ Move stores as `vector<u8>`, using string in Python
    timestamp: int
    mailbox_id: str  # ✅ Message belongs to a Mailbox

class MessageResponse(BaseModel):
    id: int  # ✅ Matches u64 in Sui
    sender: str
    receiver: str
    cid: str
    timestamp: int
    mailbox_id: str

# ✉️ MessageWithNFT Model
class MessageWithNFTCreate(BaseModel):
    sender: str
    receiver: str
    cid: str  # ✅ Move stores as `vector<u8>`, using string in Python
    timestamp: int
    nft_object_id: Optional[str] = None  # ✅ Option<address>
    claim_price: Optional[int] = None  # ✅ Option<u64>
    mailbox_id: str  # ✅ Message belongs to a Mailbox

class MessageWithNFTResponse(BaseModel):
    id: int  # ✅ Matches u64 in Sui
    sender: str
    receiver: str
    cid: str
    timestamp: int
    nft_object_id: Optional[str] = None
    claim_price: Optional[int] = None
    mailbox_id: str

# 📩 Fetch Messages Response Model
class MailboxMessagesResponse(BaseModel):
    mailbox_id: str
    messages: List[MessageResponse] = []
    messages_with_nft: List[MessageWithNFTResponse] = []

# 🏪 MailboxRegistry Model
class MailboxRegistryCreate(BaseModel):
    owner_wallet: str
    mailbox_id: str

class MailboxRegistryResponse(BaseModel):
    id: int
    owner_wallet: str
    mailbox_id: str

# 🏪 Kiosk Models
class KioskCreate(BaseModel):
    kiosk_id: str
    owner_wallet: str

class KioskResponse(BaseModel):
    kiosk_id: str
    owner_wallet: str
    items: List["KioskItemResponse"] = []  # ✅ List of items in the kiosk

# 🛒 Kiosk Item Models
class KioskItemCreate(BaseModel):
    item_id: str
    kiosk_id: str
    title: str
    content_cid: str
    price: float

class KioskItemResponse(BaseModel):
    item_id: str
    kiosk_id: str
    title: str
    content_cid: str
    price: float

# ✏️ Profile Update Model
class ProfileUpdate(BaseModel):
    profile_id: str
    new_bio: str

# 🎁 NFT Transfer Model
class NFTTransfer(BaseModel):
    recipient: str
    nft_id: str

# Update forward references for nested models
MailboxResponse.update_forward_refs()
KioskResponse.update_forward_refs()