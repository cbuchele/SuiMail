from pysui import PysuiConfiguration, SyncGqlClient
from pysui.sui.sui_pgql.pgql_sync_txn import SuiTransaction

cfg = PysuiConfiguration(group_name=PysuiConfiguration.SUI_GQL_RPC_GROUP)
client = SyncGqlClient(pysui_config=cfg)
txn = SuiTransaction(client=client)

# Function to register a user and create a mailbox
def register_user_on_chain(user_wallet: str, username: str, display_name: str, bio: str, avatar_cid: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="register_profile",
        arguments=[user_wallet, username, display_name, bio, avatar_cid]
    )

    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="messaging_with_nft",
        function="init_mailbox",
        arguments=[]
    )

    response = txn.execute(tx_builder)
    
    if not response or not response.succeeded:
        raise Exception("Blockchain transaction failed")
    
    return response

# Function to update user profile bio
def update_user_bio_on_chain(profile_id: str, new_bio: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="update_profile",
        arguments=[profile_id, new_bio]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Profile update failed")
    
    return response

# Function to send a message
def send_message_on_chain(sender_wallet: str, recipient_wallet: str, bank_id: str, payment_object: str, message_content: str):
    sender_mailbox = get_mailbox_id(sender_wallet)
    recipient_mailbox = get_mailbox_id(recipient_wallet)
    
    if not sender_mailbox or not recipient_mailbox:
        raise Exception("Mailbox not found")
    
    encoded_cid = list(message_content.encode("utf-8"))
    clock_id = "0x6"
    
    tx_builder = txn.new_transaction()
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="messaging_with_nft",
        function="send_message",
        arguments=[sender_mailbox, recipient_mailbox, bank_id, payment_object, encoded_cid, clock_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Message sending failed")
    
    return response

# Function to delete a message reference from a mailbox
def delete_message_on_chain(mailbox_id: str, message_id: int, owner_wallet: str):
    tx_builder = txn.new_transaction()
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="messaging_with_nft",
        function="delete_message",
        arguments=[mailbox_id, message_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Message deletion failed")
    
    return response

# Function to delete an entire mailbox
def delete_mailbox_on_chain(mailbox_id: str, owner_wallet: str):
    tx_builder = txn.new_transaction()
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="messaging_with_nft",
        function="delete_mailbox",
        arguments=[mailbox_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Mailbox deletion failed")
    
    return response
# Helper function to get a mailbox ID
def get_mailbox_id(wallet_address: str):
    response = client.get_objects(address=wallet_address)
    mailbox = next((obj for obj in response.result_data if "::messaging_with_nft::Mailbox" in obj.type), None)
    return mailbox.object_id if mailbox else None




# Function to update user profile
def update_profile_on_chain(profile_id: str, display_name: str, bio: str, avatar_cid: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="update_profile",
        arguments=[profile_id, display_name, bio, avatar_cid]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Profile update failed")
    
    return response

# Function to link a kiosk to a profile
def link_kiosk_on_chain(profile_id: str, kiosk_id: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="link_kiosk",
        arguments=[profile_id, kiosk_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Kiosk linking failed")
    
    return response

# Function to reset a user profile (admin only)
def reset_profile_on_chain(profile_id: str, admin_cap: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="reset_profile",
        arguments=[profile_id, admin_cap]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Profile reset failed")
    
    return response

# Function to delete a user profile
def delete_profile_on_chain(profile_id: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="profile",
        function="delete_profile",
        arguments=[profile_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Profile deletion failed")
    
    return response

# Function to initialize a kiosk
def init_kiosk_on_chain(owner_wallet: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="init_kiosk",
        arguments=[]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Kiosk initialization failed")
    
    return response

# Function to publish an item to a kiosk
def publish_item_on_chain(kiosk_id: str, title: str, content_cid: str, price: int):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="publish_item",
        arguments=[kiosk_id, title, content_cid, price]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Item publication failed")
    
    return response

# Function to delete an item from a kiosk
def delete_item_on_chain(kiosk_id: str, item_id: int):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="delete_item",
        arguments=[kiosk_id, item_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Item deletion failed")
    
    return response

# Function to buy an item from a kiosk
def buy_item_on_chain(kiosk_id: str, item_id: int, payment: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="buy_item",
        arguments=[kiosk_id, item_id, payment]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Item purchase failed")
    
    return response

# Function to withdraw funds from a kiosk
def withdraw_funds_on_chain(kiosk_id: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="withdraw_funds",
        arguments=[kiosk_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Funds withdrawal failed")
    
    return response

# Function to delete a kiosk (admin only)
def delete_kiosk_on_chain(admin_cap: str, kiosk_id: str):
    tx_builder = txn.new_transaction()
    
    tx_builder.move_call(
        package="<PACKAGE_ID>",
        module="kiosk",
        function="delete_kiosk",
        arguments=[admin_cap, kiosk_id]
    )
    
    response = txn.execute(tx_builder)
    if not response or not response.succeeded:
        raise Exception("Kiosk deletion failed")
    
    return response