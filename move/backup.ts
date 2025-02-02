 

/**
 * Function to update an existing profile.
 */
export async function updateProfile(signer, profileId, displayName, bio, avatarCid) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::profile::update_profile`,
      arguments: [
        tx.object(profileId),
        tx.pure.string(displayName),
        tx.pure.string(bio),
        tx.pure.string(avatarCid),
      ],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to delete a profile.
   */
  export async function deleteProfile(signer, profileId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::profile::delete_profile`,
      arguments: [tx.object(profileId)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  
  
  /**
   * Function to check if a user already has a profile.
   * @param {string} address - The wallet address to check.
   * @returns {Promise<boolean>}
   */
  export async function checkProfileExists(address: string): Promise<boolean> {
    try {
      const response = await client.getOwnedObjects({
        owner: address,
        filter: { StructType: `${PACKAGE_ID}::profile::UserProfile` },
      });
  
      const objects = response?.data ?? [];
      return objects.length > 0;
    } catch (error) {
      console.error('Error checking profile existence:', error);
      throw new Error('Failed to check profile existence');
    }
  }
  
  
  
  /**
   * Function to reset a user profile (Admin only).
   */
  export async function resetProfile(signer, profileId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::profile::reset_profile`,
      arguments: [tx.object(profileId), tx.object(ADMIN_CAP_ID)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  
  /**
   * Function to initialize a new kiosk.
   */
  export async function initKiosk(signer) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::kiosk::init_kiosk`,
      arguments: [],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to publish an item in the kiosk.
   */
  export async function publishItem(signer, kioskId, title, contentCid, price) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::kiosk::publish_item`,
      arguments: [tx.object(kioskId), tx.pure.string(title), tx.pure.string(contentCid), tx.pure.u64(price)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to buy an item from the kiosk.
   */
  export async function buyItem(signer, kioskId, itemId, paymentCoinId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::kiosk::buy_item`,
      arguments: [tx.object(kioskId), tx.pure.string(itemId), tx.object(paymentCoinId)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to withdraw funds from the kiosk.
   */
  export async function withdrawFunds(signer, kioskId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::kiosk::withdraw_funds`,
      arguments: [tx.object(kioskId)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to delete the kiosk (Admin only).
   */
  export async function deleteKiosk(signer, kioskId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::kiosk::delete_kiosk`,
      arguments: [tx.object(kioskId), tx.object(ADMIN_CAP_ID)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to fetch kiosk details by ID.
   * @param {string} kioskId
   * @returns {Promise<object>}
   */
  export async function getKioskDetails(kioskId) {
    try {
      const { data } = await client.getObject({ id: kioskId });
      return data.details.data.fields;
    } catch (error) {
      console.error('Error fetching kiosk details:', error);
      throw new Error('Failed to fetch kiosk details');
    }
  }
  
  /**
   * Function to initialize a new mailbox.
   */
  export async function initMailbox(signer) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::messaging_with_nft::init_mailbox`,
      arguments: [],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to send a message with optional NFT.
   */
  export async function sendMessageWithNFT(signer, mailboxId, cid, nftObjectId, claimPrice) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::messaging_with_nft::send_message_with_nft`,
      arguments: [tx.object(mailboxId), tx.pure.string(cid), tx.pure.address(nftObjectId), tx.pure.u64(claimPrice)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to claim an NFT from a message.
   */
  export async function claimNFT(signer, mailboxId, messageId, paymentCoinId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::messaging_with_nft::claim_nft`,
      arguments: [tx.object(mailboxId), tx.pure.address(messageId), tx.object(paymentCoinId)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to delete a message.
   */
  export async function deleteMessage(signer, mailboxId, messageId) {
    const tx = createTx();
    tx.moveCall({
      target: `${PACKAGE_ID}::messaging_with_nft::delete_message`,
      arguments: [tx.object(mailboxId), tx.pure.address(messageId)],
    });
    tx.setGasBudget(10000);
    return await signer.signAndExecuteTransaction({ transaction: tx });
  }
  
  /**
   * Function to fetch the mailbox state for a given wallet address.
   */
  export async function fetchMailboxState(address) {
    try {
      const objects = await client.getOwnedObjects({
        owner: address,
        filter: { StructType: `${PACKAGE_ID}::messaging_with_nft::Mailbox` },
      });
      return objects.length > 0;
    } catch (error) {
      console.error('Error fetching mailbox state:', error);
      throw new Error('Failed to fetch mailbox state');
    }
  }
  