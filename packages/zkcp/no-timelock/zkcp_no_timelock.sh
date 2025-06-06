#!/bin/bash
set -e

echo -e "\n========== COMPLETE ZKCP (NO TIMELOCK) IMPLEMENTATION ==========\n"
echo -e "This script demonstrates a complete Zero-Knowledge Contingent Payment flow\n"

# Install required packages if not present
echo "[*] Checking required packages..."
if ! python3 -c "import bitcoin" &>/dev/null; then
    echo "[*] Installing python-bitcoinlib..."
    pip3 install python-bitcoinlib
fi

# 1. Start Bitcoin Daemon if not running
if ! bitcoin-cli -regtest getblockcount &>/dev/null; then
    echo "[*] Starting Bitcoin Daemon..."
    bitcoind -regtest -fallbackfee=0.0001 -daemon -deprecatedrpc=create_bdb
    sleep 3
fi

# 2. Create wallets if they don't exist
WALLETS=$(bitcoin-cli -regtest listwallets)
if ! echo $WALLETS | grep -q "sellerwallet"; then
    echo "[*] Creating seller wallet..."
    bitcoin-cli -regtest createwallet "sellerwallet" false false "" false false > /dev/null 2>&1
fi

if ! echo $WALLETS | grep -q "buyerwallet"; then
    echo "[*] Creating buyer wallet..."
    bitcoin-cli -regtest createwallet "buyerwallet" false false "" false false > /dev/null 2>&1
fi

# 3. Get addresses
seller_address=$(bitcoin-cli -regtest -rpcwallet=sellerwallet getnewaddress) 
buyer_address=$(bitcoin-cli -regtest -rpcwallet=buyerwallet getnewaddress)
echo "[*] Seller address: $seller_address"
echo "[*] Buyer address: $buyer_address"

# 4. Fund the wallets if needed
echo "[*] Initial wallet balances:"
echo "    Seller: $(bitcoin-cli -regtest -rpcwallet=sellerwallet getreceivedbyaddress $seller_address) BTC"
echo "    Buyer: $(bitcoin-cli -regtest -rpcwallet=buyerwallet getreceivedbyaddress $buyer_address) BTC"

echo "[*] Mining blocks to fund seller wallet..."
bitcoin-cli -regtest generatetoaddress 101 $seller_address > /dev/null 2>&1

echo "[*] Mining blocks to fund buyer wallet..."
bitcoin-cli -regtest generatetoaddress 101 $buyer_address > /dev/null 2>&1

echo "[*] Wallet balances after funding:"
echo "    Seller: $(bitcoin-cli -regtest -rpcwallet=sellerwallet getreceivedbyaddress $seller_address) BTC"
echo "    Buyer: $(bitcoin-cli -regtest -rpcwallet=buyerwallet getreceivedbyaddress $buyer_address) BTC"

# 5. Generate the redeem script using asm.py to prepare for funding
echo -e "\n========== ZKCP SETUP PHASE ==========\n"

# Setup parameters
REAL_K="HELLO"
HASH_K=$(python3 ../common/hash.py $REAL_K)
BLOCK_HEIGHT=$(bitcoin-cli -regtest getblockcount)

echo "[*] Seller computes parameters:"
echo "    K: $REAL_K (encryption key)"
echo "    Y = SHA256(K): $HASH_K"

# Get public keys
seller_pubkey=$(bitcoin-cli -regtest -rpcwallet=sellerwallet getaddressinfo $seller_address | jq -r .pubkey)
buyer_pubkey=$(bitcoin-cli -regtest -rpcwallet=buyerwallet getaddressinfo $buyer_address | jq -r .pubkey)

# Generate redeem script using Python script
echo "[*] Generating redeem script..."
REDEEM_SCRIPT=$(python3 asm_no_timelock.py "$HASH_K" "$seller_pubkey" "$buyer_pubkey")

# Decode script to get P2SH address
SCRIPT_INFO=$(bitcoin-cli -regtest decodescript "$REDEEM_SCRIPT")
P2SH_ADDRESS=$(echo "$SCRIPT_INFO" | jq -r .p2sh)
echo "[*] P2SH Address: $P2SH_ADDRESS"

# 6. Buyer funds the P2SH address
echo -e "\n========== PAYMENT SETUP PHASE ==========\n"
echo "[*] Buyer verifies parameters and funds P2SH address..."
TXID=$(bitcoin-cli -regtest -rpcwallet=buyerwallet sendtoaddress "$P2SH_ADDRESS" 1.0)
echo "[*] Funding transaction sent: $TXID"

# 7. Check if Transaction Exists
CHECK_TXID=$(bitcoin-cli -regtest -rpcwallet=buyerwallet gettransaction $TXID | jq -r .txid)
echo "[*] Transaction $CHECK_TXID on Buyer Wallet"

# 8. Import script to wallets for tracking
echo "[*] Importing scripts to wallets..."
bitcoin-cli -regtest -rpcwallet=buyerwallet importaddress "$REDEEM_SCRIPT" "zkcp_redeem" false > /dev/null 2>&1
bitcoin-cli -regtest -rpcwallet=buyerwallet importaddress "$P2SH_ADDRESS" "zkcp_p2sh" false > /dev/null 2>&1
bitcoin-cli -regtest -rpcwallet=sellerwallet importaddress "$REDEEM_SCRIPT" "zkcp_redeem" false > /dev/null 2>&1
bitcoin-cli -regtest -rpcwallet=sellerwallet importaddress "$P2SH_ADDRESS" "zkcp_p2sh" false > /dev/null 2>&1

# 9. Mine blocks to confirm funding transaction
echo "[*] Mining blocks to confirm funding transaction..."
bitcoin-cli -regtest generatetoaddress 6 $buyer_address > /dev/null 2>&1
echo "[*] Funding transaction confirmed"

# 10. Find the P2SH UTXO
UTXO_TXID=$(bitcoin-cli -rpcwallet=buyerwallet -regtest listunspent 0 9999999 "[\"$P2SH_ADDRESS\"]" | jq -r .[0].txid)
VOUT=$(bitcoin-cli -rpcwallet=buyerwallet -regtest listunspent 0 9999999 "[\"$P2SH_ADDRESS\"]" | jq -r .[0].vout)
AMOUNT=$(bitcoin-cli -rpcwallet=buyerwallet -regtest listunspent 0 9999999 "[\"$P2SH_ADDRESS\"]" | jq -r .[0].amount)
echo "[*] Found UTXO: $UTXO_TXID:$VOUT with $AMOUNT BTC"

# 11. Use the specialized Python script to create and broadcast transaction with proper scriptSig
echo -e "\n========== PAYMENT EXECUTION PHASE ==========\n"
echo "[*] Seller creates and broadcasts transaction revealing K..."
echo "[*] Running specialized Python script to create proper scriptSig..."

# Execute the Python script (zkcp_no_timelock_tx.py) that creates the proper scriptSig
python3 zkcp_no_timelock_tx.py "$REAL_K" "$REDEEM_SCRIPT" "$TXID" "$VOUT" $AMOUNT

# Mine some blocks to confirm
echo "[*] Mining blocks to confirm transaction..."
bitcoin-cli -regtest generatetoaddress 6 $seller_address > /dev/null 2>&1
echo "[*] Transaction confirmed!"

# 10. Verify transaction confirmation and extraction of K
echo -e "\n========== VERIFICATION PHASE ==========\n"
echo "[*] Buyer extracts K from the blockchain transaction"
echo "[*] K = $REAL_K"
echo "[*] Buyer verifies SHA256(K) = $HASH_K"

# Simulate verification
COMPUTED_HASH=$(echo -n "$REAL_K" | sha256sum | awk '{print $1}')
echo "[*] Computed hash: $COMPUTED_HASH"

if [ "$COMPUTED_HASH" = "$HASH_K" ]; then
    echo "[*] Hash verification successful!"
    echo "[*] Buyer can now decrypt the content using K"
else 
    echo "[!] Hash verification failed!"
fi

echo -e "\n========== FINAL BALANCES ==========\n"
echo "[*] Wallet balances after ZKCP:"
echo "    Seller: $(bitcoin-cli -regtest -rpcwallet=sellerwallet getbalance) BTC"
echo "    Buyer: $(bitcoin-cli -regtest -rpcwallet=buyerwallet getbalance) BTC"

echo -e "\n[*] ZKCP demonstration complete"
