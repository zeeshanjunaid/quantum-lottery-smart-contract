// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

contract ShowStats is Script, QuantumLotteryTypes {
    function run() external view {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address lotteryAddr = vm.envAddress("LOTTERY");
        QuantumLottery lottery = QuantumLottery(lotteryAddr);

        uint256 nowTs = block.timestamp;
        uint256 currHour = nowTs / SECONDS_PER_HOUR;
        uint256 prevHour = currHour > 0 ? currHour - 1 : 0;

        address owner = lottery.owner();
    console.log("USDC:", usdc);
    console.log("Lottery:", lotteryAddr);
    console.log("Owner:", owner);
    console.log("Now (ts):", nowTs);
    console.log("Current hour:", currHour);
    console.log("Previous hour:", prevHour);

        _printHour(lottery, usdc, currHour, "current");
        if (prevHour != currHour) {
            _printHour(lottery, usdc, prevHour, "previous");
        }

        // Owner stats
        (uint64 lastPlayedHr, uint32 streak, uint256 qScore) = lottery.players(owner);
        uint256 bal = IERC20(usdc).balanceOf(owner);
        console.log("--- Owner Stats ---");
        console.log("address:", owner);
        console.log("usdcBalance:", bal);
        console.log("streak:", uint256(streak));
        console.log("qScore:", qScore);
        console.log("lastPlayedHour:", uint256(lastPlayedHr));
    }

    function _printHour(
        QuantumLottery lottery,
        address usdc,
        uint256 hourId,
        string memory label
    ) internal view {
        uint256 count = lottery.getParticipantsCount(hourId);
    console.log("=== Hour label:", label);
    console.log("hourId:", hourId);
    console.log("participants:", count);
        for (uint256 i = 0; i < count; i++) {
            QuantumLotteryTypes.Participant memory p = lottery.getParticipant(hourId, i);
            (uint64 lastPlayedHr, uint32 streak, uint256 qScore) = lottery.players(p.playerAddress);
            uint256 bal = IERC20(usdc).balanceOf(p.playerAddress);
            console.log("#", i);
            console.log("address:", p.playerAddress);
            console.log("ticketType:", uint256(p.ticketTypeOnEntry));
            console.log("qScoreOnEntry:", p.qScoreOnEntry);
            console.log("usdcBalance:", bal);
            console.log("streak:", uint256(streak));
            console.log("qScore:", qScore);
            console.log("lastPlayedHour:", uint256(lastPlayedHr));
        }
    }
}
