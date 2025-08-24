// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";
import {TestUSDC} from "../src/TestUSDC.sol";

/// @notice Simple on-chain smoke: mint tUSDC (owner), approve, and buy a Standard ticket
contract SmokeBuy is Script {
    function run() external {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address lottery = vm.envAddress("LOTTERY");
        // Use the configured broadcaster key so the intended owner joins
        bytes32 pkb = vm.envBytes32("PRIVATE_KEY");
        vm.startBroadcast(uint256(pkb));

        // Mint funds if using our TestUSDC (owner-only); harmless no-op on real USDC as it would revert.
        // Assumes the broadcast key is the TestUSDC owner (as in prior deploys).
        try TestUSDC(usdc).mint(msg.sender, 1_000e6) {
            // minted 1,000 tUSDC
        } catch {
            // ignore if not TestUSDC or not owner
        }

        // Pick ticket type from env: TICKET_TYPE=0 (Standard) or 1 (Quantum)
        uint256 ttEnv = vm.envOr("TICKET_TYPE", uint256(0));
        QuantumLotteryTypes.TicketType tt =
            ttEnv == 1 ? QuantumLotteryTypes.TicketType.Quantum : QuantumLotteryTypes.TicketType.Standard;

        // Approve max and buy a ticket
        IERC20(usdc).approve(lottery, type(uint256).max);
        QuantumLottery(lottery).buyTicket(tt);

        vm.stopBroadcast();
    }
}
