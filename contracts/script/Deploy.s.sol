// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {PilotRegistry, PilotCard} from "../src/PilotRegistry.sol";
import {ConservativeRWA} from "../src/ConservativeRWA.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract Deploy is Script {
    address constant USDC_ARB_SEPOLIA = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    uint256 constant MIN_STAKE = 5e6;
    uint256 constant REFERENCE_PILOT_STAKE = 5e6;

    function run() external {
        address deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        address usdcAddr = vm.envOr("USDC_ADDRESS", USDC_ARB_SEPOLIA);
        address reputation = vm.envOr("ERC8004_REPUTATION", address(0));

        console.log("Deployer :", deployer);
        console.log("Chain ID :", block.chainid);
        console.log("ERC-8004 :", reputation);

        vm.startBroadcast();

        VaultFactory factory = new VaultFactory(reputation);
        PilotRegistry registry = new PilotRegistry(usdcAddr, MIN_STAKE);
        ConservativeRWA conservativeRWA = new ConservativeRWA();

        console.log("VaultFactory    :", address(factory));
        console.log("PilotRegistry   :", address(registry));
        console.log("ConservativeRWA :", address(conservativeRWA));

        IERC20 usdc = IERC20(usdcAddr);
        if (usdc.balanceOf(deployer) >= REFERENCE_PILOT_STAKE) {
            usdc.approve(address(registry), REFERENCE_PILOT_STAKE);

            address[] memory chains = new address[](1);
            chains[0] = address(uint160(block.chainid));

            uint256 pilotId = registry.registerPilot(
                PilotCard({
                    name: "ConservativeRWA",
                    description: "Maintains USDC/aUSDC target allocation via Aave V3. Rebalances when drift exceeds 5%.",
                    riskProfile: "conservative",
                    ipfsMetadata: "",
                    supportedChains: chains
                }),
                address(conservativeRWA),
                deployer,
                REFERENCE_PILOT_STAKE
            );
            console.log("ConservativeRWA pilot id:", pilotId);
        } else {
            console.log("WARN: insufficient USDC - register pilot manually after getting testnet USDC");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("Add to .env:");
        console.log(string.concat("VAULT_FACTORY=",     vm.toString(address(factory))));
        console.log(string.concat("PILOT_REGISTRY=",    vm.toString(address(registry))));
        console.log(string.concat("CONSERVATIVE_RWA=",  vm.toString(address(conservativeRWA))));
        console.log("");
        console.log("Then run: forge script script/DeployOracle.s.sol ...");
        console.log("Then run: ./scripts/setup-vault.sh");
    }
}
