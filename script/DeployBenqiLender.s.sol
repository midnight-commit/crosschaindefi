// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import {BenqiLender} from "../src/BenqiLender.sol";

contract DeployBenqiLender is Script {
    address public constant WRAPPED_NATIVE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function run() external {
        vm.startBroadcast();
        new BenqiLender(WRAPPED_NATIVE);
        vm.stopBroadcast();
    }
}

// forge script script/DeployBenqiLender.s.sol:DeployBenqiLender --rpc-url $CCHAIN_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast -vvvv --optimize --optimizer-runs 200 --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key "verifyContract"
