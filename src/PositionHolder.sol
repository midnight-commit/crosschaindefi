// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract PositionHolder {
    using Address for address;

    address public user;
    address public crossChainLender;

    modifier requiresAuth() virtual {
        require(msg.sender == crossChainLender || msg.sender == user, "UNAUTHORIZED");

        _;
    }

    constructor(address senderOrigin) {
        crossChainLender = msg.sender;
        user = senderOrigin;
    }

    function manage(address target, bytes calldata data, uint256 value)
        external
        requiresAuth
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    receive() external payable {}
}
