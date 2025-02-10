from fastapi import FastAPI, Depends, HTTPException, status
from sqlalchemy.orm import Session
from models import SessionLocal, User, MessageWithNFT ,Kiosk,KioskItem, Mailbox
from pydantic_models import MailboxCreate, MailboxMessagesResponse, MessageWithNFTCreate, UserCreate, AdminLogin, MessageCreate, ProfileUpdate, NFTTransfer, KioskCreate, KioskItemCreate
from passlib.context import CryptContext
from datetime import datetime, timedelta
from jose import JWTError, jwt
from pydantic_models import AdminCreate
from sqlalchemy.exc import IntegrityError
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pysui.sui.sui_pgql.pgql_sync_txn import SuiTransaction
from cryptography.fernet import Fernet
from typing import Any


# JWT Config
SECRET_KEY = "suimailrocks"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

# Generate a key and save it securely (store this key in your environment variables)
key = Fernet.generate_key()
cipher = Fernet(key)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")
app = FastAPI()

# Dependency for DB Session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Authenticate User
def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        wallet_address: str = payload.get("sub")
        if wallet_address is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        user = db.query(User).filter(User.wallet_address == wallet_address).first()
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
        return user
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials")

# 🔑 User Login & Token Generation
@app.post("/auth/token")
def login(wallet_address: str, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.wallet_address == wallet_address).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not registered")
    
    access_token = jwt.encode({"sub": wallet_address}, SECRET_KEY, algorithm=ALGORITHM)
    return {"access_token": access_token, "token_type": "bearer"}

# 👤 Register User (Called after on-chain transaction)
@app.post("/register")
def register_user(user: UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.wallet_address == user.wallet_address).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="User already registered")

    db_user = User(**user.dict())
    db.add(db_user)
    db.commit()
    return {"message": "User registered successfully"}

# ✏️ Update Profile
@app.post("/update_profile")
def update_profile(profile: ProfileUpdate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.wallet_address == current_user.wallet_address).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    user.bio = profile.new_bio
    db.commit()
    return {"message": "Profile updated successfully"}

# 📬 Create Mailbox
@app.post("/create_mailbox")
def create_mailbox(mailbox: MailboxCreate, db: Session = Depends(get_db)):
    existing_mailbox = db.query(Mailbox).filter(Mailbox.mailbox_id == mailbox.mailbox_id).first()
    if existing_mailbox:
        raise HTTPException(status_code=400, detail="Mailbox already exists")

    db_mailbox = Mailbox(**mailbox.dict())
    db.add(db_mailbox)
    db.commit()
    return {"message": "Mailbox created successfully"}

# Encrypt the message content before storing it
@app.post("/store_message")
def store_message(msg: MessageCreate, db: Session = Depends(get_db)):
    if not msg.cid:
        raise HTTPException(status_code=400, detail="CID cannot be empty")

    try:
        # Encrypt the content (if needed)
        encrypted_content = cipher.encrypt(msg.content.encode()).decode() if msg.content else None
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error encrypting message content: {str(e)}"
        )

    # Create the MessageWithNFT object with the provided CID
    db_msg = MessageWithNFT(
        sender=msg.sender,
        receiver=msg.receiver,
        cid=msg.cid,  # Store the CID directly
        content=encrypted_content,  # Store the encrypted content (if any)
        timestamp=msg.timestamp,
        nft_object_id=msg.nft_object_id,
        claim_price=msg.claim_price,
        mailbox_id=msg.mailbox_id
    )
    db.add(db_msg)
    db.commit()
    return {"message": "Message stored successfully"}

# 📬 Get User Messages
@app.get("/messages")
def get_messages(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    messages = db.query(MessageWithNFT).filter(
        (MessageWithNFT.sender == current_user.wallet_address) |
        (MessageWithNFT.receiver == current_user.wallet_address)
    ).all()

    response = []
    for msg in messages:
        try:
            # Decrypt the content (if encrypted)
            decrypted_content = cipher.decrypt(msg.content.encode()).decode() if msg.content else None
            response.append({
                "id": msg.id,
                "sender": msg.sender,
                "receiver": msg.receiver,
                "cid": msg.cid,  # Return the CID
                "content": decrypted_content,  # Decrypted content (if any)
                "timestamp": msg.timestamp,
                "nft_object_id": msg.nft_object_id,
                "claim_price": msg.claim_price,
                "mailbox_id": msg.mailbox_id
            })
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Error decrypting message content: {str(e)}"
            )

    return response

# 🏪 **Create Kiosk (Called after on-chain transaction)**
@app.post("/create_kiosk")
def create_kiosk(kiosk: KioskCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    existing_kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == kiosk.kiosk_id).first()
    if existing_kiosk:
        raise HTTPException(status_code=400, detail="Kiosk already exists")

    db_kiosk = Kiosk(**kiosk.dict())
    db.add(db_kiosk)
    db.commit()
    return {"message": "Kiosk created successfully"}

# 🔗 Link Kiosk to User Profile (After On-Chain Transaction)
@app.post("/link_kiosk")
def link_kiosk(profile_id: str, kiosk_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    user = db.query(User).filter(User.wallet_address == current_user.wallet_address).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Update the user profile in the database
    user.kiosk_id = kiosk_id
    db.commit()
    
    return {"message": "Kiosk linked successfully"}

# 🔍 **Get All Kiosks**
@app.get("/kiosks")
def get_all_kiosks(db: Session = Depends(get_db)):
    kiosks = db.query(Kiosk).all()
    return kiosks


# 🏪 **Get a Specific Kiosk**
@app.get("/kiosk/{kiosk_id}")
def get_kiosk(kiosk_id: str, db: Session = Depends(get_db)):
    kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == kiosk_id).first()
    if not kiosk:
        raise HTTPException(status_code=404, detail="Kiosk not found")
    return kiosk





# 🛒 **Add Item to Kiosk (Called after on-chain transaction)**
@app.post("/add_kiosk_item")
def add_kiosk_item(item: KioskItemCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == item.kiosk_id, Kiosk.owner_wallet == current_user.wallet_address).first()
    if not kiosk:
        raise HTTPException(status_code=403, detail="Not authorized or kiosk does not exist")

    db_item = KioskItem(**item.dict())
    db.add(db_item)
    db.commit()
    return {"message": "Item added successfully"}

# 🛍️ **Get All Items in a Kiosk**
@app.get("/store/{kiosk_id}")
def get_store_items(kiosk_id: str, db: Session = Depends(get_db)):
    items = db.query(KioskItem).filter(KioskItem.kiosk_id == kiosk_id).all()
    return items

# ❌ **Delete an Item from the Kiosk (Only Owner)**
@app.delete("/delete_kiosk_item/{item_id}")
def delete_kiosk_item(item_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    item = db.query(KioskItem).filter(KioskItem.item_id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == item.kiosk_id, Kiosk.owner_wallet == current_user.wallet_address).first()
    if not kiosk:
        raise HTTPException(status_code=403, detail="Not authorized to delete this item")

    db.delete(item)
    db.commit()
    return {"message": "Item deleted successfully"}


# 💰 **Buy Item from Kiosk (Called after on-chain transaction)**
@app.post("/buy_kiosk_item/{item_id}")
def buy_kiosk_item(item_id: str, db: Session = Depends(get_db)):
    item = db.query(KioskItem).filter(KioskItem.item_id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    # In the frontend, this transaction is executed first on Sui blockchain
    db.delete(item)  # Remove item from database after successful purchase
    db.commit()
    return {"message": "Item purchased successfully"}


# 💵 **Withdraw Funds from Kiosk (Owner Only)**
@app.post("/withdraw_funds/{kiosk_id}")
def withdraw_funds(kiosk_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == kiosk_id, Kiosk.owner_wallet == current_user.wallet_address).first()
    if not kiosk:
        raise HTTPException(status_code=403, detail="Not authorized to withdraw funds")

    # In frontend, this transaction is executed first on-chain
    return {"message": f"Funds withdrawn successfully for Kiosk {kiosk_id}"}

# ❌ **Delete Entire Kiosk (Owner Only)**
@app.delete("/delete_kiosk/{kiosk_id}")
def delete_kiosk(kiosk_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    kiosk = db.query(Kiosk).filter(Kiosk.kiosk_id == kiosk_id, Kiosk.owner_wallet == current_user.wallet_address).first()
    if not kiosk:
        raise HTTPException(status_code=403, detail="Not authorized to delete this kiosk")

    db.delete(kiosk)
    db.commit()
    return {"message": "Kiosk deleted successfully"}