// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {Vault} from "../src/Vault.sol";
import {Charter, Action} from "../src/interfaces/IVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";
import {MockERC8004Reputation} from "./mocks/MockERC8004Reputation.sol";

event Deposited(address indexed token, uint256 amount);
event PilotHired(address indexed pilot, uint256 charterExpiry);
event PilotRevoked(address indexed pilot);
event ActionExecuted(address indexed pilot, Action action, bool success);

contract VaultTest is Test {
    VaultFactory factory;
    Vault vault;
    MockERC20 usdc;
    MockAavePool aave;

    address captain = makeAddr("captain");
    address pilot = makeAddr("pilot");
    address stranger = makeAddr("stranger");

    uint256 constant DEPOSIT_AMOUNT = 10_000e6;

    function setUp() public {
        factory = new VaultFactory(address(0));
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aave = new MockAavePool();

        vm.prank(captain);
        address vaultAddr = factory.createVault();
        vault = Vault(payable(vaultAddr));

        usdc.mint(captain, DEPOSIT_AMOUNT);
        vm.startPrank(captain);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_deposit_transfersTokens() public view {
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_deposit_emitsEvent() public {
        usdc.mint(captain, 1e6);
        vm.startPrank(captain);
        usdc.approve(address(vault), 1e6);
        vm.expectEmit(true, false, false, true);
        emit Deposited(address(usdc), 1e6);
        vault.deposit(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_deposit_revertsZeroAmount() public {
        vm.prank(captain);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit(address(usdc), 0);
    }

    function test_withdraw_captainCanWithdraw() public {
        vm.prank(captain);
        vault.withdraw(address(usdc), 1000e6, captain);
        assertEq(usdc.balanceOf(captain), 1000e6);
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT - 1000e6);
    }

    function test_withdraw_strangerCannotWithdraw() public {
        vm.prank(stranger);
        vm.expectRevert(Vault.NotCaptain.selector);
        vault.withdraw(address(usdc), 1000e6, stranger);
    }

    function test_withdraw_revertsZeroAddress() public {
        vm.prank(captain);
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.withdraw(address(usdc), 1000e6, address(0));
    }

    function test_forceWithdrawAll_drains() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(captain);
        vault.forceWithdrawAll(captain, tokens);

        assertEq(usdc.balanceOf(captain), DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_forceWithdrawAll_worksWhenPaused() public {
        vm.prank(captain);
        vault.pause();

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(captain);
        vault.forceWithdrawAll(captain, tokens);

        assertEq(usdc.balanceOf(captain), DEPOSIT_AMOUNT);
    }

    function test_forceWithdrawAll_strangerReverts() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(stranger);
        vm.expectRevert(Vault.NotCaptain.selector);
        vault.forceWithdrawAll(stranger, tokens);
    }

    function test_forceWithdrawAll_skipsZeroBalance() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(other);

        vm.prank(captain);
        vault.forceWithdrawAll(captain, tokens);

        assertEq(usdc.balanceOf(captain), DEPOSIT_AMOUNT);
    }

    function test_hirePilot_storesCharter() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        Charter memory stored = vault.getCharter(pilot);
        assertEq(stored.pilot, pilot);
        assertEq(stored.maxSingleAmountIn, c.maxSingleAmountIn);
    }

    function test_hirePilot_onlyCaptain() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(stranger);
        vm.expectRevert(Vault.NotCaptain.selector);
        vault.hirePilot(c);
    }

    function test_revokePilot_removesCharter() public {
        Charter memory c = _buildCharter(pilot);
        vm.startPrank(captain);
        vault.hirePilot(c);
        vault.revokePilot(pilot);
        vm.stopPrank();

        vm.prank(pilot);
        vm.expectRevert(Vault.NoPilotCharter.selector);
        Action[] memory empty = new Action[](0);
        vault.executePlan(empty);
    }

    function test_pause_blocksPilotExecution() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        vm.prank(captain);
        vault.pause();

        vm.prank(pilot);
        vm.expectRevert(Vault.AlreadyPaused.selector);
        Action[] memory empty = new Action[](0);
        vault.executePlan(empty);
    }

    function test_unpause_allowsExecution() public {
        Charter memory c = _buildCharter(pilot);
        vm.startPrank(captain);
        vault.hirePilot(c);
        vault.pause();
        vault.unpause();
        vm.stopPrank();

        vm.prank(pilot);
        Action[] memory empty = new Action[](0);
        vault.executePlan(empty);
    }

    function test_pause_revertsIfAlreadyPaused() public {
        vm.startPrank(captain);
        vault.pause();
        vm.expectRevert(Vault.AlreadyPaused.selector);
        vault.pause();
        vm.stopPrank();
    }

    function test_unpause_revertsIfNotPaused() public {
        vm.prank(captain);
        vm.expectRevert(Vault.NotCurrentlyPaused.selector);
        vault.unpause();
    }

    function test_captainWithdrawWorksWhilePaused() public {
        vm.startPrank(captain);
        vault.pause();
        vault.withdraw(address(usdc), 1000e6, captain);
        vm.stopPrank();
        assertEq(usdc.balanceOf(captain), 1000e6);
    }

    function test_executePlan_revertsWithoutCharter() public {
        vm.prank(pilot);
        vm.expectRevert(Vault.NoPilotCharter.selector);
        Action[] memory empty = new Action[](0);
        vault.executePlan(empty);
    }

    function test_executePlan_revertsExpiredCharter() public {
        vm.warp(1000);
        Charter memory c = _buildCharter(pilot);
        c.expiresAt = block.timestamp - 1;
        vm.prank(captain);
        vault.hirePilot(c);

        vm.prank(pilot);
        vm.expectRevert(Vault.CharterExpired.selector);
        Action[] memory empty = new Action[](0);
        vault.executePlan(empty);
    }

    function test_executePlan_revertsInvalidAction() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(0xDEAD),
            callData: "",
            value: 0,
            tokenIn: address(usdc),
            amountIn: 100e6,
            tokenOut: address(0)
        });

        vm.prank(pilot);
        vm.expectRevert(abi.encodeWithSelector(Vault.ValidationFailed.selector, "target not in charter whitelist"));
        vault.executePlan(actions);
    }

    function test_executePlan_successWithAaveSupply() public {
        usdc.mint(address(aave), 100_000e6);

        Charter memory c = _buildCharter(pilot);
        address[] memory targets = new address[](1);
        targets[0] = address(aave);
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(usdc);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = address(aave.aToken());
        c.allowedTargets = targets;
        c.allowedTokensIn = tokensIn;
        c.allowedTokensOut = tokensOut;

        vm.prank(captain);
        vault.hirePilot(c);

        bytes memory callData = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            address(usdc),
            1000e6,
            address(vault),
            uint16(0)
        );

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(aave),
            callData: callData,
            value: 0,
            tokenIn: address(usdc),
            amountIn: 1000e6,
            tokenOut: address(aave.aToken())
        });

        vm.prank(pilot);
        vault.executePlan(actions);

        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT - 1000e6);
        assertEq(aave.aToken().balanceOf(address(vault)), 1000e6);
    }

    function test_executePlan_dailyLimitReset() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        assertEq(vault.getDailySpent(pilot), 0);

        vm.warp(block.timestamp + 2 days);
        assertEq(vault.getDailySpent(pilot), 0);
    }

    function test_executePlan_blocksTokenOutZeroWhenSpending() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(aave),
            callData: abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)",
                address(usdc), 1000e6, pilot, uint16(0)
            ),
            value: 0,
            tokenIn: address(usdc),
            amountIn: 1000e6,
            tokenOut: address(0)
        });

        vm.prank(pilot);
        vm.expectRevert(abi.encodeWithSelector(Vault.TokenOutRequiredWhenSpending.selector, 0));
        vault.executePlan(actions);

        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_executePlan_blocksTokenOutToExternalAddress() public {
        usdc.mint(address(aave), 100_000e6);

        aave.aToken().mint(address(vault), 1000e6);
        aave.supplied_set(address(vault), 1000e6);

        address attacker = makeAddr("attacker");

        Charter memory c = _buildCharter(pilot);
        address[] memory targets = new address[](1);
        targets[0] = address(aave);
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(aave.aToken());
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = address(usdc);
        c.allowedTargets = targets;
        c.allowedTokensIn = tokensIn;
        c.allowedTokensOut = tokensOut;

        vm.prank(captain);
        vault.hirePilot(c);

        bytes memory maliciousCallData = abi.encodeWithSignature(
            "withdraw(address,uint256,address)",
            address(usdc),
            1000e6,
            attacker
        );

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(aave),
            callData: maliciousCallData,
            value: 0,
            tokenIn: address(aave.aToken()),
            amountIn: 1000e6,
            tokenOut: address(usdc)
        });

        vm.prank(pilot);
        vm.expectRevert(abi.encodeWithSelector(Vault.TokenOutNotReceived.selector, 0));
        vault.executePlan(actions);

        assertEq(usdc.balanceOf(attacker), 0);
        assertEq(usdc.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_executePlan_blocksEthValue() public {
        Charter memory c = _buildCharter(pilot);
        vm.prank(captain);
        vault.hirePilot(c);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(aave),
            callData: "",
            value: 1 ether,
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0)
        });

        vm.prank(pilot);
        vm.expectRevert(abi.encodeWithSelector(Vault.EthValueNotAllowed.selector, 0));
        vault.executePlan(actions);
    }

    function test_initialize_revertsIfCalledTwice() public {
        vm.expectRevert(Vault.AlreadyInitialized.selector);
        vault.initialize(captain, address(0));
    }

    function test_executePlan_postsErc8004Feedback() public {
        MockERC8004Reputation rep = new MockERC8004Reputation();
        VaultFactory repFactory = new VaultFactory(address(rep));

        vm.prank(captain);
        Vault repVault = Vault(payable(repFactory.createVault()));

        usdc.mint(captain, DEPOSIT_AMOUNT);
        vm.startPrank(captain);
        usdc.approve(address(repVault), DEPOSIT_AMOUNT);
        repVault.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        usdc.mint(address(aave), 100_000e6);

        address[] memory targets = new address[](1);
        targets[0] = address(aave);
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(usdc);
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = address(aave.aToken());

        Charter memory c = Charter({
            pilot: pilot,
            allowedTargets: targets,
            allowedTokensIn: tokensIn,
            allowedTokensOut: tokensOut,
            maxSingleAmountIn: 5000e6,
            maxDailyAmountIn: 20_000e6,
            expiresAt: 0
        });

        vm.prank(captain);
        repVault.hirePilot(c);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(aave),
            callData: abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)",
                address(usdc), 1000e6, address(repVault), uint16(0)
            ),
            value: 0,
            tokenIn: address(usdc),
            amountIn: 1000e6,
            tokenOut: address(aave.aToken())
        });

        vm.prank(pilot);
        repVault.executePlan(actions);

        assertEq(rep.getFeedbackCount(pilot), 1);
        assertEq(rep.getScore(pilot), 1);
    }

    function _buildCharter(address _pilot) internal view returns (Charter memory c) {
        address[] memory targets = new address[](1);
        targets[0] = address(aave);
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = address(usdc);
        address[] memory tokensOut = new address[](0);

        c = Charter({
            pilot: _pilot,
            allowedTargets: targets,
            allowedTokensIn: tokensIn,
            allowedTokensOut: tokensOut,
            maxSingleAmountIn: 5000e6,
            maxDailyAmountIn: 20_000e6,
            expiresAt: 0
        });
    }
}
