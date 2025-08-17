// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {TestUSDC} from "../src/TestUSDC.sol";

contract TestUSDCScript is Script {
    function run() external returns (address) {
        vm.startBroadcast();
        TestUSDC testUsdc = new TestUSDC();
        vm.stopBroadcast();
        return address(testUsdc);
    }
}
