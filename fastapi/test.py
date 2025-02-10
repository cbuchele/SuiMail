from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from models import SessionLocal, User, MessageWithNFT ,Kiosk,KioskItem, Mailbox
from pydantic_models import MailboxCreate, MailboxMessagesResponse, MessageWithNFTCreate, UserCreate, MessageCreate, ProfileUpdate, NFTTransfer, KioskCreate, KioskItemCreate
from passlib.context import CryptContext
from datetime import datetime, timedelta
from jose import JWTError, jwt
from sqlalchemy.exc import IntegrityError
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
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

# CORS configuration
origins = [
    "http://localhost:3000",  # Frontend application
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
def login(address: str, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.address == address).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not registered")
    
    access_token = jwt.encode({"sub": address}, SECRET_KEY, algorithm=ALGORITHM)
    return {"access_token": access_token, "token_type": "bearer"}

# 👤 Register User (Called after on-chain transaction)
@app.post("/register")
def register_user(user: UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.address == user.address).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="User already registered")

    db_user = User(**user.dict())
    db.add(db_user)
    db.commit()
    return {"message": "User registered successfully"}
# 📬 Create Mailbox

@app.post("/create_mailbox")
def create_mailbox(mailbox: MailboxCreate, db: Session = Depends(get_db)):
    existing_mailbox = db.query(Mailbox).filter(Mailbox.mailbox_id == mailbox.mailbox_id).first()
    if existing_mailbox:
        raise HTTPException(status_code=400, detail="Mailbox already exists")

    db_mailbox = Mailbox(
        mailbox_id=mailbox.mailbox_id,
        owner_address=mailbox.owner_address
    )
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