// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IVRFSubscriptionV2Plus} from
    "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

/// @notice Cancels a single Chainlink VRF v2.5 subscription and sends remaining LINK to WITHDRAW_TO.
/// Env vars required:
/// - VRF_COORDINATOR (address)  — v2.5 coordinator address
/// - SUB_ID_TO_CANCEL (uint256) — subscription id to cancel
/// - WITHDRAW_TO (address)      — recipient for refunded LINK
/// Recommended to broadcast with the subscription owner key: --private-key $PRIVATE_KEY
contract CancelVRFSub is Script {
    function run() external {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subId = vm.envUint("SUB_ID_TO_CANCEL");
        address to = vm.envAddress("WITHDRAW_TO");

        vm.startBroadcast();
        IVRFSubscriptionV2Plus(coordinator).cancelSubscription(subId, to);
        vm.stopBroadcast();
    }
}
