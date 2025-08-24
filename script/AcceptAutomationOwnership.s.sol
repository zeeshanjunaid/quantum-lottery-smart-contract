// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LotteryAutomation} from "../src/LotteryAutomation.sol";

contract AcceptAutomationOwnership is Script {
    function run() external {
        address keeper = vm.envAddress("KEEPER");
        vm.startBroadcast();
        LotteryAutomation(keeper).acceptLotteryOwnership();
        vm.stopBroadcast();
        console.log("Accepted lottery ownership via keeper", keeper);
    }
}
