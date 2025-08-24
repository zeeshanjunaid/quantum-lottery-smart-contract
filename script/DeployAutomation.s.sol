// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {LotteryAutomation} from "../src/LotteryAutomation.sol";

contract DeployAutomation is Script {
    function run() external returns (address keeper) {
        address lotteryAddr = vm.envAddress("LOTTERY");
        uint256 iters = vm.envOr("AUTOMATION_ITER", uint256(100));

        vm.startBroadcast();
        LotteryAutomation k = new LotteryAutomation(lotteryAddr, iters);
        keeper = address(k);

        // Transfer ownership of the Lottery to the keeper; operator must later call acceptLotteryOwnership
        QuantumLottery(lotteryAddr).transferOwnership(keeper);
        vm.stopBroadcast();

        console.log("LotteryAutomation deployed:", keeper);
        console.log("IMPORTANT: Now run acceptLotteryOwnership() by broadcasting from keeper owner or add a helper.");
        return keeper;
    }
}
