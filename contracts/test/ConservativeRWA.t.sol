// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ConservativeRWA} from "../src/ConservativeRWA.sol";
import {Action, Charter} from "../src/interfaces/IVault.sol";

contract ConservativeRWATest is Test {
    ConservativeRWA pilot;

    function setUp() public {
        pilot = new ConservativeRWA();
    }

    function test_riskProfile_isConservative() public view {
        assertEq(pilot.riskProfile(), "conservative");
    }

    function test_supportedAssets_returnsNonEmptyList() public view {
        address[] memory assets = pilot.supportedAssets();
        assertTrue(assets.length > 0);
    }

    function test_computeDrifts_balanced() public view {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 5000e18;
        balances[1] = 5000e18;

        uint256[] memory targets = new uint256[](2);
        targets[0] = 5000;
        targets[1] = 5000;

        int256[] memory drifts = pilot.computeDrifts(balances, targets);
        assertEq(drifts[0], 0);
        assertEq(drifts[1], 0);
    }

    function test_computeDrifts_overweightFirst() public view {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 7000e18;
        balances[1] = 3000e18;

        uint256[] memory targets = new uint256[](2);
        targets[0] = 6000;
        targets[1] = 4000;

        int256[] memory drifts = pilot.computeDrifts(balances, targets);
        assertGt(drifts[0], 0);
        assertLt(drifts[1], 0);
    }

    function test_computeDrifts_emptyVault() public view {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        uint256[] memory targets = new uint256[](2);
        targets[0] = 6000;
        targets[1] = 4000;

        int256[] memory drifts = pilot.computeDrifts(balances, targets);
        assertEq(drifts[0], 0);
        assertEq(drifts[1], 0);
    }

    function test_computeDrifts_revertsLengthMismatch() public {
        uint256[] memory balances = new uint256[](2);
        uint256[] memory targets = new uint256[](3);
        vm.expectRevert("length mismatch");
        pilot.computeDrifts(balances, targets);
    }

    function test_shouldRebalance_trueWhenDriftExceedsThreshold() public view {
        int256[] memory drifts = new int256[](2);
        drifts[0] = int256(ConservativeRWA(pilot).DRIFT_THRESHOLD_BPS());
        drifts[1] = 0;
        assertTrue(pilot.shouldRebalance(drifts));
    }

    function test_shouldRebalance_falseWhenDriftBelowThreshold() public view {
        int256[] memory drifts = new int256[](2);
        drifts[0] = int256(ConservativeRWA(pilot).DRIFT_THRESHOLD_BPS()) - 1;
        drifts[1] = 0;
        assertFalse(pilot.shouldRebalance(drifts));
    }

    function test_shouldRebalance_trueOnNegativeDrift() public view {
        int256[] memory drifts = new int256[](1);
        drifts[0] = -int256(ConservativeRWA(pilot).DRIFT_THRESHOLD_BPS());
        assertTrue(pilot.shouldRebalance(drifts));
    }

    function test_shouldRebalance_falseAllZero() public view {
        int256[] memory drifts = new int256[](3);
        assertFalse(pilot.shouldRebalance(drifts));
    }

    function test_encodeAaveSupply_returnsNonEmptyCalldata() public view {
        bytes memory cd = pilot.encodeAaveSupply(address(0x1), 1000e6, address(0x2));
        assertTrue(cd.length > 0);
        bytes4 expected = bytes4(keccak256("supply(address,uint256,address,uint16)"));
        bytes4 actual;
        assembly {
            actual := mload(add(cd, 32))
        }
        assertEq(actual, expected);
    }

    function test_encodeAaveWithdraw_returnsNonEmptyCalldata() public view {
        bytes memory cd = pilot.encodeAaveWithdraw(address(0x1), 1000e6, address(0x2));
        assertTrue(cd.length > 0);
        bytes4 expected = bytes4(keccak256("withdraw(address,uint256,address)"));
        bytes4 actual;
        assembly {
            actual := mload(add(cd, 32))
        }
        assertEq(actual, expected);
    }

    function test_validatePlan_passesEmptyPlan() public view {
        Charter memory charter = _buildCharter();
        Action[] memory actions = new Action[](0);
        assertTrue(pilot.validatePlan(actions, charter));
    }

    function test_validatePlan_failsUnknownTarget() public view {
        Charter memory charter = _buildCharter();
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            target: address(0xDEAD),
            callData: "",
            value: 0,
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0)
        });
        assertFalse(pilot.validatePlan(actions, charter));
    }

    function testFuzz_computeDrifts_twoAssets(uint256 b0, uint256 b1) public view {
        b0 = bound(b0, 0, 1e30);
        b1 = bound(b1, 0, 1e30);
        uint256[] memory balances = new uint256[](2);
        balances[0] = b0;
        balances[1] = b1;
        uint256[] memory targets = new uint256[](2);
        targets[0] = 5000;
        targets[1] = 5000;
        int256[] memory drifts = pilot.computeDrifts(balances, targets);
        assertEq(drifts.length, 2);
    }

    function _buildCharter() internal view returns (Charter memory c) {
        address[] memory targets = new address[](1);
        targets[0] = pilot.AAVE_POOL();
        address[] memory tokensIn = new address[](1);
        tokensIn[0] = pilot.USDC();
        address[] memory tokensOut = new address[](1);
        tokensOut[0] = pilot.A_USDC();

        c = Charter({
            pilot: address(pilot),
            allowedTargets: targets,
            allowedTokensIn: tokensIn,
            allowedTokensOut: tokensOut,
            maxSingleAmountIn: 5000e6,
            maxDailyAmountIn: 20_000e6,
            expiresAt: 0
        });
    }
}
