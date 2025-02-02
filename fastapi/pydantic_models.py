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

# 📬 Mailbox Model (Each User has One Mailbox)
class MailboxCreate(BaseModel):
    mailbox_id: str
    owner_wallet: str

# ✉️ MessageWithNFT Model
class MessageWithNFTCreate(BaseModel):
    id: int  # ✅ Matches u64 in Sui
    sender: str
    receiver: str
    cid: str  # ✅ Move stores as `vector<u8>`, using string in Python
    timestamp: int
    nft_object_id: Optional[str] = None  # ✅ Option<address>
    claim_price: Optional[int] = None  # ✅ Option<u64>
    mailbox_id: str  # ✅ Message belongs to a Mailbox

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
