// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {Vault} from "../src/Vault.sol";

event VaultCreated(address indexed captain, address indexed vault, uint256 timestamp);

contract VaultFactoryTest is Test {
    VaultFactory factory;
    address captain = makeAddr("captain");
    address captain2 = makeAddr("captain2");

    function setUp() public {
        factory = new VaultFactory(address(0));
    }

    function test_createVault_deploysFreshVault() public {
        vm.prank(captain);
        address vault = factory.createVault();
        assertTrue(vault != address(0));
        assertEq(Vault(payable(vault)).captain(), captain);
    }

    function test_createVault_registersInMapping() public {
        vm.prank(captain);
        address vault = factory.createVault();
        assertEq(factory.vaultOf(captain), vault);
    }

    function test_createVault_emitsEvent() public {
        vm.prank(captain);
        vm.expectEmit(true, false, false, false);
        emit VaultCreated(captain, address(0), block.timestamp);
        factory.createVault();
    }

    function test_createVault_revertsDuplicate() public {
        vm.startPrank(captain);
        factory.createVault();
        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.createVault();
        vm.stopPrank();
    }

    function test_createVault_differentCaptainsGetDifferentVaults() public {
        vm.prank(captain);
        address v1 = factory.createVault();

        vm.prank(captain2);
        address v2 = factory.createVault();

        assertTrue(v1 != v2);
        assertEq(factory.vaultOf(captain), v1);
        assertEq(factory.vaultOf(captain2), v2);
    }

    function test_allVaultsCount() public {
        assertEq(factory.allVaultsCount(), 0);

        vm.prank(captain);
        factory.createVault();
        assertEq(factory.allVaultsCount(), 1);

        vm.prank(captain2);
        factory.createVault();
        assertEq(factory.allVaultsCount(), 2);
    }

    function test_allVaults_paginationWorks() public {
        address[] memory captains = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            captains[i] = makeAddr(string(abi.encodePacked("captain", i)));
            vm.prank(captains[i]);
            factory.createVault();
        }
        assertEq(factory.allVaultsCount(), 5);

        address[] memory page = factory.allVaults(0, 3);
        assertEq(page.length, 3);

        address[] memory rest = factory.allVaults(3, 10);
        assertEq(rest.length, 2);
    }

    function test_implementationIsNotUsable() public view {
        address impl = factory.vaultImplementation();
        assertEq(Vault(payable(impl)).captain(), address(0));
    }
}
