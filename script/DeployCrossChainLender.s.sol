// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import {CrossChainLender} from "../src/CrossChainLender.sol";
import {IComptroller} from "../src/interfaces/IBenqi.sol";

contract DeployCrossChainLender is Script {
    address constant BENQI_COMPTROLLER_AVALANCHE = 0xD7c4006d33DA2A0A8525791ed212bbCD7Aca763F;

    function run() external {
        // Retrieve the private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy CrossChainLender with network-specific comptroller
        CrossChainLender lender = new CrossChainLender(BENQI_COMPTROLLER_AVALANCHE);

        console.log("CrossChainLender deployed at:", address(lender));

        vm.stopBroadcast();
    }
}

// forge script script/DeployCrossChainLender.s.sol:DeployCrossChainLender --rpc-url $CCHAIN_RPC_URL --broadcast -vvvv --optimize --optimizer-runs 200 --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key "verifyContract"
