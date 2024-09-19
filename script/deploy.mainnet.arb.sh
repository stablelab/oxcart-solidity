source .env

# To deploy and verify our contract
forge script script/Oxcart.s.sol:DeployOxcart --rpc-url $RPC_URL_MAINNET_ARB --broadcast --etherscan-api-key $ARBSCAN_API_KEY --sender $PUBLIC_KEY --verify -vvvv
