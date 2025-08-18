// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LinkTokenInterface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

/// @notice Fund a Chainlink VRF v2 Subscription using LINK transferAndCall
contract FundVRFSub is Script {
    function run() external {
        address link = vm.envAddress("LINK_TOKEN");
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint64 subId = uint64(vm.envUint("VRF_SUBSCRIPTION_ID"));
        uint256 amount = vm.envUint("LINK_AMOUNT"); // in juels (1 LINK = 1e18)

        vm.startBroadcast();
        // transferAndCall(address to, uint256 value, bytes data)
        bool ok = LinkTokenInterface(link).transferAndCall(
            coordinator,
            amount,
            abi.encode(subId)
        );
        require(ok, "LINK transferAndCall failed");
        vm.stopBroadcast();
    }
}
