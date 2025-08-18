// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

/// @notice Compare per-participant stats for the just-ended (previous) hour
contract CompareStats is Script, QuantumLotteryTypes {
    function run() external view {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address lotteryAddr = vm.envAddress("LOTTERY");
        QuantumLottery lottery = QuantumLottery(lotteryAddr);

        uint256 nowTs = block.timestamp;
        uint256 currHour = nowTs / SECONDS_PER_HOUR;
    // Optional TARGET_HOUR (e.g., two hours ago). Defaults to previous hour if not provided.
    uint256 targetHour = vm.envOr("TARGET_HOUR", currHour > 0 ? currHour - 1 : 0);

    // Draw summary (for target hour)
    uint256 pot = lottery.getPrizePot(targetHour);
    address winner = lottery.getWinner(targetHour);
    QuantumLotteryTypes.DrawStatus status = lottery.getDrawStatus(targetHour);
        uint256 winnerPayout = (pot * WINNER_PAYOUT_PERCENT) / PERCENTAGE_TOTAL;
        uint256 feeAmount = pot - winnerPayout;

    console.log("=== Draw Summary (target hour) ===");
    console.log("targetHour:", targetHour);
        console.log("status:", uint256(status)); // 0 OPEN,1 CALCULATING_WINNER,2 RESOLVING,3 RESOLVED
        console.log("pot (raw):", pot);
        console.log("pot (t$):", pot / 1_000_000);
        console.log("winner:", winner);
        console.log("winnerPayout (t$):", winnerPayout / 1_000_000);
        console.log("fee (t$):", feeAmount / 1_000_000);

        uint256 count = lottery.getParticipantsCount(targetHour);
        console.log("participants:", count);

        for (uint256 i = 0; i < count; i++) {
            QuantumLotteryTypes.Participant memory p = lottery.getParticipant(targetHour, i);
            (uint64 lastPlayedHr, uint32 streak, uint256 qScoreNow) = lottery.players(p.playerAddress);
            bool isWinner = (p.playerAddress == winner);
            string memory ttype = p.ticketTypeOnEntry == QuantumLotteryTypes.TicketType.Quantum
                ? "Quantum"
                : "Standard";

            console.log("#", i);
            console.log("name:", _name(p.playerAddress));
            console.log("address:", p.playerAddress);
            console.log("ticket:", ttype);
            console.log("qScore pre:", p.qScoreOnEntry);
            console.log("qScore now:", qScoreNow);
            if (qScoreNow >= p.qScoreOnEntry) {
                console.log("qScore delta:+", qScoreNow - p.qScoreOnEntry);
            } else {
                console.log("qScore delta:-", p.qScoreOnEntry - qScoreNow);
            }
            console.log("streak now:", uint256(streak));
            console.log("lastPlayedHour:", uint256(lastPlayedHr));
            console.log("isWinner:", isWinner);
            uint256 bal = IERC20(usdc).balanceOf(p.playerAddress);
            console.log("balance (t$):", bal / 1_000_000);
        }

        // Also show treasury and lottery balances for quick fee/payout sanity
        address treasury = lottery.i_treasury();
        uint256 tBal = IERC20(usdc).balanceOf(treasury);
        uint256 lBal = IERC20(usdc).balanceOf(lotteryAddr);
        console.log("--- Accounts ---");
        console.log("treasury:", treasury);
        console.log("treasury balance (t$):", tBal / 1_000_000);
        console.log("lottery balance (t$):", lBal / 1_000_000);
    }

    function _name(address a) internal pure returns (string memory) {
        // Known demo labels used in our testnet session
        if (a == 0x94cF685cc5D26828e2CA4c9C571249Fc9B1D16Be) return "Zeeshan"; // owner
        if (a == 0x335c3009548F4A392E72B7D062E13Fb27338A47A) return "Alice";
        if (a == 0x783C89d1F3B8707aD191c4B86Dd44E901b4F6De9) return "Bob";
        if (a == 0xdF0777621bA83142ddd349eeAE122f132f41b61B) return "Charlie";
        if (a == 0xF1c8194d42F50C64685604fea60F23Ade0fFBA76) return "Diana";
        if (a == 0xb1138094397f7F3EF1200C123E1539c6a5AD1738) return "Ethan";
        if (a == 0xE7daB1389F7aBDc16044F61CEdfcC5086012E0B4) return "Farah";
        return "(unknown)";
    }
}
