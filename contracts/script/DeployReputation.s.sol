// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC8004Reputation} from "../test/mocks/MockERC8004Reputation.sol";

contract DeployReputation is Script {
    function run() external {
        vm.startBroadcast();

        MockERC8004Reputation reputation = new MockERC8004Reputation();
        console.log("MockERC8004Reputation deployed:", address(reputation));

        vm.stopBroadcast();

        console.log("");
        console.log("Add to .env:");
        console.log(string.concat("ERC8004_REPUTATION=", vm.toString(address(reputation))));
    }
}
