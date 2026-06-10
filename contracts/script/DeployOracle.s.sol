// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockOracle} from "../src/MockOracle.sol";

contract DeployOracle is Script {
    address constant USDC_ARB = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant A_USDC = 0x460b97BD498E1157530AEb3086301d5225b91216;

    function run() external {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        console.log("MockOracle deployed:", address(oracle));

        address[] memory tokens = new address[](2);
        uint256[] memory prices = new uint256[](2);
        string[] memory symbols = new string[](2);

        tokens[0] = USDC_ARB;  prices[0] = 1e18;  symbols[0] = "USDC";   
        tokens[1] = A_USDC;    prices[1] = 1e18;  symbols[1] = "aUSDC"; 

        oracle.setPrices(tokens, prices, symbols);
        console.log("Prices seeded: USDC=$1.00, aUSDC=$1.00");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Oracle ready ===");
        console.log(string.concat("ORACLE_ADDRESS=", vm.toString(address(oracle))));
        console.log("");
        console.log("Add to .env:");
        console.log(string.concat("ORACLE_ADDRESS=", vm.toString(address(oracle))));
        console.log(string.concat("NEXT_PUBLIC_ORACLE=", vm.toString(address(oracle))));
    }
}
