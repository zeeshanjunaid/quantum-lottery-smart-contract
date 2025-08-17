// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";

contract DeployScript is Script {
    function run() external returns (address) {
        // Load all the constructor arguments from your .env file
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint64 subscriptionId = uint64(vm.envUint("VRF_SUBSCRIPTION_ID"));
        bytes32 gasLane = vm.envBytes32("GAS_LANE");

        // Start broadcasting the transaction
        vm.startBroadcast();

        // Deploy the contract with the loaded variables
        QuantumLottery lottery =
            new QuantumLottery(usdcAddress, treasuryAddress, vrfCoordinator, subscriptionId, gasLane);

        // Stop broadcasting
        vm.stopBroadcast();
        return address(lottery);
    }
}
