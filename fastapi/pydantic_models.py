from pydantic import BaseModel
from typing import Optional, List


# 👤 User Models
class UserCreate(BaseModel):
    wallet_address: str
    username: str
    display_name: str
    bio: str
    avatar_cid: str

class MessageCreate(BaseModel):
    sender: str
    receiver: str
    cid: str
    content: str  # Added content field
    timestamp: int
    nft_object_id: Optional[str] = None
    claim_price: Optional[int] = None
    mailbox_id: str

class MessageWithNFTCreate(BaseModel):
    id: int
    sender: str
    receiver: str
    cid: str
    content: str  # Added content field
    timestamp: int
    nft_object_id: Optional[str] = None
    claim_price: Optional[int] = None
    mailbox_id: str

# 📩 Fetch Messages Response Model
class MailboxMessagesResponse(BaseModel):
    mailbox_id: str
    messages: List[MessageWithNFTCreate]

# 🏪 Kiosk Models
class KioskCreate(BaseModel):
    kiosk_id: str
    owner_wallet: str

# 🛒 Kiosk Item Models
class KioskItemCreate(BaseModel):
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

# 📬 Mailbox Create Model
class MailboxCreate(BaseModel):
    mailbox_id: str
    owner_wallet: str