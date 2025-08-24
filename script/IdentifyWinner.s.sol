// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";

/// @notice Identify the winner by name for a completed draw
contract IdentifyWinner is Script {
    string[] private NAMES = [
        "Ahmed",    // 0 - Quantum
        "Ayesha",   // 1 - Quantum
        "Bilal",    // 2 - Quantum
        "Fatima",   // 3 - Quantum
        "Hassan",   // 4 - Quantum
        "Hina",     // 5 - Quantum
        "Imran",    // 6 - Quantum
        "Iqra",     // 7 - Standard
        "Junaid",   // 8 - Standard
        "Kiran",    // 9 - Standard
        "Mariam",   // 10 - Standard
        "Noman",    // 11 - Standard
        "Omar",     // 12 - Standard
        "Rabia",    // 13 - Standard
        "Saad",     // 14 - Standard
        "Sana",     // 15 - Standard
        "Talha",    // 16 - Standard
        "Uzma",     // 17 - Standard
        "Yasir",    // 18 - Standard
        "Zara",     // 19 - Standard
        "Asad",     // 20+
        "Fariha",
        "Danish",
        "Hammad",
        "Nida",
        "Sadia",
        "Shahzad",
        "Mahnoor",
        "Kamran",
        "Zainab"
    ];

    function run() external view {
        address lottery = vm.envAddress("LOTTERY");
        uint256 hourId = vm.envOr("HOUR_ID", uint256(0));
        
        if (hourId == 0) {
            // Default to previous hour
            hourId = block.timestamp / 3600 - 1;
        }
        
        console.log("=== WINNER IDENTIFICATION ===");
        console.log("Hour ID:", hourId);
        
        address winner = QuantumLottery(lottery).getWinner(hourId);
        console.log("Winner address:", winner);
        
        if (winner == address(0)) {
            console.log("No winner found for this hour");
            return;
        }
        
        uint256 pot = QuantumLottery(lottery).getPrizePot(hourId);
        uint256 payout = pot * 92 / 100;
        
        console.log("Prize pot:", pot);
        console.log("Winner payout:", payout);
        
        // Try to identify the winner by deriving participant addresses
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        bool found = false;
        
        for (uint256 i = 0; i < 30 && !found; i++) {
            uint256 pk = uint256(keccak256(abi.encode(ownerPk, i + 777)));
            address participantAddr = vm.addr(pk);
            
            if (participantAddr == winner) {
                string memory name = i < NAMES.length ? NAMES[i] : "Unknown";
                string memory ticketType = i < 7 ? "Quantum" : "Standard";
                uint256 entryFee = i < 7 ? 30 : 10;
                
                console.log("");
                console.log("WINNER IDENTIFIED!");
                console.log("Name:", name);
                console.log("Participant #:", i + 1);
                console.log("Ticket Type:", ticketType);
                console.log("Entry Fee:", entryFee, "USDC");
                console.log("Prize Won:", payout / 1000000, "USDC");
                console.log("Net Profit:", (payout / 1000000) - entryFee, "USDC");
                
                uint256 roi = ((payout / 1000000) - entryFee) * 100 / entryFee;
                console.log("ROI:", roi, "%");
                
                found = true;
            }
        }
        
        if (!found) {
            console.log("Winner not found in participant list");
            console.log("This might be a different type of winner or external address");
        }
    }
}
