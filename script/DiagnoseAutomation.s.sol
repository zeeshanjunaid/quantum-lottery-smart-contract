// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LotteryAutomation} from "../src/LotteryAutomation.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

contract DiagnoseAutomation is Script, QuantumLotteryTypes {
    function run() external view {
        address keeper = vm.envAddress("KEEPER");
        address lotteryAddr = vm.envAddress("LOTTERY");
        QuantumLottery lottery = QuantumLottery(lotteryAddr);

        uint256 nowTs = block.timestamp;
        uint256 currHour = nowTs / SECONDS_PER_HOUR;
        uint256 targetHour = currHour > 0 ? currHour - 1 : 0;

        console.log("Now:", nowTs);
        console.log("Current hour:", currHour);
        console.log("Target hour:", targetHour);

        DrawStatus status = lottery.getDrawStatus(targetHour);
        uint256 participants = lottery.getParticipantsCount(targetHour);
        uint256 reqTs = lottery.getRequestTimestamp(targetHour);
        bool cleanup = lottery.isCleanupPending(targetHour);

        console.log("status (0=OPEN,1=CALCULATING,2=RESOLVING,3=RESOLVED):", uint256(status));
        console.log("participants:", participants);
        console.log("requestTimestamp:", reqTs);
        console.log("cleanupPending:", cleanup);

        // checkUpkeep simulation
        (bool needed, bytes memory data) = LotteryAutomation(keeper).checkUpkeep("");
        console.log("checkUpkeep: needed=", needed);
        if (needed) {
            (uint8 action, uint256 hourId) = abi.decode(data, (uint8, uint256));
            console.log("action:", action); // 1=request,2=process,3=cleanup,4=force
            console.log("hourId:", hourId);
        } else {
            console.log("No upkeep needed. Likely reasons:");
            console.log("- Still in current hour (targetHour not finished yet)");
            console.log("- Not enough participants (minParticipants not met)");
            console.log("- Already resolved and no cleanup pending");
        }
    }
}
