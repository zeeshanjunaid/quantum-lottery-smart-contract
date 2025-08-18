// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";
import {TestUSDC} from "../src/TestUSDC.sol";

/// @notice Funds N ephemeral EOAs with ETH and tUSDC, then each buys a ticket.
/// Uses the broadcaster as the TestUSDC owner for minting and as the ETH funder.
contract MultiJoin is Script {
    function run() external {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address lottery = vm.envAddress("LOTTERY");
    uint256 count = vm.envOr("JOIN_COUNT", uint256(5));
    // How many of the participants should buy a Quantum ticket (rest will be Standard)
    uint256 quantumCount = vm.envOr("QUANTUM_COUNT", uint256(2));
    uint256 ethPer = vm.envOr("ETH_PER_JOIN_WEI", uint256(200000000000000)); // 0.0002 ETH
    uint256 usdcPer = vm.envOr("USDC_PER_JOIN", uint256(10_000_000)); // 10 USDC (6 decimals)

        // Derive participant private keys deterministically for testnet and fund them
        // NOTE: For real tests, set your own keys via env and adapt this script.
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");

        // 1) As owner: fund ETH and mint USDC to each participant
        vm.startBroadcast(ownerPk);
        for (uint256 i = 0; i < count; i++) {
            // Derive a deterministic test key range: keccak(ownerPk, i) truncated
            uint256 pk = uint256(keccak256(abi.encode(ownerPk, i + 777)));
            address participantAddr = vm.addr(pk);
            // fund ETH for gas
            (bool ok, ) = payable(participantAddr).call{value: ethPer}("");
            require(ok, "ETH fund failed");
            // mint tUSDC to participant (no-op if USDC is not TestUSDC owned by broadcaster)
            try TestUSDC(usdc).mint(participantAddr, usdcPer) {
                // minted
            } catch {
                // ignore if not owner or token is not TestUSDC
            }
        }
        vm.stopBroadcast();

        // 2) Each participant approves and buys a ticket
        for (uint256 i = 0; i < count; i++) {
            uint256 pk = uint256(keccak256(abi.encode(ownerPk, i + 777)));
            vm.startBroadcast(pk);
            // approve and buy (alternate ticket types)
            IERC20(usdc).approve(lottery, type(uint256).max);
            // First quantumCount will buy Quantum, remaining buy Standard
            QuantumLotteryTypes.TicketType tt = (i < quantumCount)
                ? QuantumLotteryTypes.TicketType.Quantum
                : QuantumLotteryTypes.TicketType.Standard;
            try QuantumLottery(lottery).buyTicket(tt) {
                // bought
            } catch {
                // ignore if already entered this hour
            }
            vm.stopBroadcast();
        }
    }
}
