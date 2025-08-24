// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LotteryAutomation} from "../src/LotteryAutomation.sol";

contract ConfigAutomation is Script {
    function run() external {
        address keeper = vm.envAddress("KEEPER");
        uint256 iters = vm.envOr("AUTOMATION_ITER", uint256(100));
        uint256 minP = vm.envOr("AUTOMATION_MIN_PARTICIPANTS", uint256(1));
        bool force = vm.envOr("AUTOMATION_FORCE_RESOLVE", true);

        vm.startBroadcast();
        LotteryAutomation(keeper).setIterations(iters);
        LotteryAutomation(keeper).setMinParticipants(minP);
        LotteryAutomation(keeper).setForceResolve(force);
        vm.stopBroadcast();
        console.log("Configured keeper:", keeper);
    }
}
