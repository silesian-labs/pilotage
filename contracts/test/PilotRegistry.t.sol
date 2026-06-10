// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PilotRegistry, PilotCard, PilotRecord} from "../src/PilotRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PilotRegistryTest is Test {
    PilotRegistry registry;
    MockERC20 usdc;

    address owner = makeAddr("owner");
    address dev = makeAddr("dev");
    address dev2 = makeAddr("dev2");
    address executor = makeAddr("executor");
    address executor2 = makeAddr("executor2");
    address stranger = makeAddr("stranger");

    uint256 constant MIN_STAKE = 1000e6;

    PilotCard basePilotCard;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        vm.prank(owner);
        registry = new PilotRegistry(address(usdc), MIN_STAKE);

        basePilotCard = PilotCard({
            name: "ConservativeRWA",
            description: "Low-risk RWA allocation pilot",
            riskProfile: "conservative",
            ipfsMetadata: "ipfs://Qm000",
            supportedChains: new address[](0)
        });

        usdc.mint(dev, 10_000e6);
        usdc.mint(dev2, 10_000e6);
    }

    function test_registerPilot_succeedsWithSufficientStake() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
        assertEq(id, 1);
    }

    function test_registerPilot_storesRecord() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        PilotRecord memory p = registry.getPilot(id);
        assertEq(p.developer, dev);
        assertEq(p.executor, executor);
        assertEq(p.card.name, "ConservativeRWA");
        assertTrue(p.active);
        assertFalse(p.slashed);
        assertEq(p.stakedAmount, MIN_STAKE);
    }

    function test_registerPilot_takesStake() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
        assertEq(usdc.balanceOf(address(registry)), MIN_STAKE);
        assertEq(usdc.balanceOf(dev), 10_000e6 - MIN_STAKE);
    }

    function test_registerPilot_emitsEvent() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        vm.expectEmit(true, true, true, true);
        emit PilotRegistry.PilotRegistered(1, dev, executor, dev, "ConservativeRWA");
        registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
    }

    function test_registerPilot_revertsInsufficientStake() public {
        uint256 tooLittle = MIN_STAKE - 1;
        usdc.mint(dev, tooLittle);
        vm.startPrank(dev);
        usdc.approve(address(registry), tooLittle);
        vm.expectRevert(PilotRegistry.InsufficientStake.selector);
        registry.registerPilot(basePilotCard, executor, dev, tooLittle);
        vm.stopPrank();
    }

    function test_registerPilot_revertsZeroExecutor() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        vm.expectRevert(PilotRegistry.ZeroAddress.selector);
        registry.registerPilot(basePilotCard, address(0), dev, MIN_STAKE);
    }

    function test_registerPilot_revertsExecutorAlreadyRegistered() public {
        _approvePilotStake(dev, MIN_STAKE * 2);
        vm.startPrank(dev);
        registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
        vm.expectRevert(PilotRegistry.ExecutorAlreadyRegistered.selector);
        registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
        vm.stopPrank();
    }

    function test_registerPilot_appearsInActiveList() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);
        assertEq(registry.activePilotCount(), 1);
        uint256[] memory ids = registry.getActivePilotIds(0, 10);
        assertEq(ids[0], 1);
    }

    function test_updatePilotCard_succeeds() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        PilotCard memory updated = basePilotCard;
        updated.name = "ConservativeRWA v2";

        vm.prank(dev);
        registry.updatePilotCard(id, updated);

        assertEq(registry.getPilot(id).card.name, "ConservativeRWA v2");
    }

    function test_updatePilotCard_revertsIfNotDeveloper() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.prank(stranger);
        vm.expectRevert(PilotRegistry.NotDeveloper.selector);
        registry.updatePilotCard(id, basePilotCard);
    }

    function test_unregisterPilot_returnsStake() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        uint256 balanceBefore = usdc.balanceOf(dev);
        vm.prank(dev);
        registry.unregisterPilot(id);

        assertEq(usdc.balanceOf(dev), balanceBefore + MIN_STAKE);
        assertFalse(registry.getPilot(id).active);
    }

    function test_unregisterPilot_removesFromActiveList() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.prank(dev);
        registry.unregisterPilot(id);

        assertEq(registry.activePilotCount(), 0);
    }

    function test_unregisterPilot_revertsIfNotDeveloper() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.prank(stranger);
        vm.expectRevert(PilotRegistry.NotDeveloper.selector);
        registry.unregisterPilot(id);
    }

    function test_slashPilot_confiscatesStake() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        uint256 ownerBefore = usdc.balanceOf(owner);
        vm.prank(owner);
        registry.slashPilot(id, "charter violation");

        assertEq(usdc.balanceOf(owner), ownerBefore + MIN_STAKE);
        assertTrue(registry.getPilot(id).slashed);
        assertFalse(registry.getPilot(id).active);
    }

    function test_slashPilot_removesFromActiveList() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.prank(owner);
        registry.slashPilot(id, "malicious");

        assertEq(registry.activePilotCount(), 0);
    }

    function test_slashPilot_revertsIfNotOwner() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.prank(stranger);
        vm.expectRevert(PilotRegistry.NotOwner.selector);
        registry.slashPilot(id, "reason");
    }

    function test_slashPilot_revertsIfAlreadySlashed() public {
        _approvePilotStake(dev, MIN_STAKE);
        vm.prank(dev);
        uint256 id = registry.registerPilot(basePilotCard, executor, dev, MIN_STAKE);

        vm.startPrank(owner);
        registry.slashPilot(id, "first slash");
        vm.expectRevert(PilotRegistry.AlreadySlashed.selector);
        registry.slashPilot(id, "second slash");
        vm.stopPrank();
    }

    function test_pagination_multipleActivePilots() public {
        for (uint256 i = 0; i < 5; i++) {
            address d = makeAddr(string(abi.encodePacked("dev", i)));
            address e = makeAddr(string(abi.encodePacked("exec", i)));
            usdc.mint(d, MIN_STAKE);
            vm.startPrank(d);
            usdc.approve(address(registry), MIN_STAKE);
            registry.registerPilot(basePilotCard, e, d, MIN_STAKE);
            vm.stopPrank();
        }
        assertEq(registry.activePilotCount(), 5);

        uint256[] memory page1 = registry.getActivePilotIds(0, 3);
        assertEq(page1.length, 3);

        uint256[] memory page2 = registry.getActivePilotIds(3, 10);
        assertEq(page2.length, 2);
    }

    function test_activeList_maintainsIntegrityAfterMiddleSlash() public {
        uint256[] memory ids = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            address d = makeAddr(string(abi.encodePacked("devM", i)));
            address e = makeAddr(string(abi.encodePacked("execM", i)));
            usdc.mint(d, MIN_STAKE);
            vm.startPrank(d);
            usdc.approve(address(registry), MIN_STAKE);
            ids[i] = registry.registerPilot(basePilotCard, e, d, MIN_STAKE);
            vm.stopPrank();
        }

        vm.prank(owner);
        registry.slashPilot(ids[1], "bad pilot");

        assertEq(registry.activePilotCount(), 2);

        uint256[] memory active = registry.getActivePilotIds(0, 10);
        for (uint256 i = 0; i < active.length; i++) {
            assertTrue(registry.getPilot(active[i]).active);
        }
    }

    function _approvePilotStake(address dev_, uint256 amount) internal {
        vm.prank(dev_);
        usdc.approve(address(registry), amount);
    }
}
