// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CharterValidator} from "../src/CharterValidator.sol";
import {Action, Charter} from "../src/interfaces/IVault.sol";

contract CharterValidatorTest is Test {
    CharterValidator validator;

    address constant AAVE = address(0xA001);
    address constant USDC = address(0xC001);
    address constant A_USDC = address(0xC002);
    address constant TSLA = address(0xC003);
    address constant ATTACKER = address(0xDEAD);

    Charter baseCharter;

    function setUp() public {
        validator = new CharterValidator();

        address[] memory targets = new address[](1);
        targets[0] = AAVE;

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = USDC;

        address[] memory tokensOut = new address[](1);
        tokensOut[0] = A_USDC;

        baseCharter = Charter({
            pilot: address(0x1),
            allowedTargets: targets,
            allowedTokensIn: tokensIn,
            allowedTokensOut: tokensOut,
            maxSingleAmountIn: 1000e6,
            maxDailyAmountIn: 5000e6,
            expiresAt: 0
        });
    }

    function test_validate_passesValidAction() public view {
        Action memory action = _buildAction(AAVE, USDC, 500e6, A_USDC);
        (bool ok, string memory reason) = validator.validate(action, baseCharter);
        assertTrue(ok);
        assertEq(bytes(reason).length, 0);
    }

    function test_validate_failsUnknownTarget() public view {
        Action memory action = _buildAction(ATTACKER, USDC, 500e6, A_USDC);
        (bool ok, string memory reason) = validator.validate(action, baseCharter);
        assertFalse(ok);
        assertEq(reason, "target not in charter whitelist");
    }

    function test_validate_failsUnknownTokenIn() public view {
        Action memory action = _buildAction(AAVE, TSLA, 500e6, A_USDC);
        (bool ok, string memory reason) = validator.validate(action, baseCharter);
        assertFalse(ok);
        assertEq(reason, "tokenIn not in charter whitelist");
    }

    function test_validate_failsUnknownTokenOut() public view {
        Action memory action = _buildAction(AAVE, USDC, 500e6, TSLA);
        (bool ok, string memory reason) = validator.validate(action, baseCharter);
        assertFalse(ok);
        assertEq(reason, "tokenOut not in charter whitelist");
    }

    function test_validate_failsExceedsSingleCap() public view {
        Action memory action = _buildAction(AAVE, USDC, 9999e6, A_USDC);
        (bool ok, string memory reason) = validator.validate(action, baseCharter);
        assertFalse(ok);
        assertEq(reason, "action exceeds maxSingleAmountIn");
    }

    function test_validate_failsExpiredCharter() public {
        vm.warp(1000);
        Charter memory expired = baseCharter;
        expired.expiresAt = block.timestamp - 1;
        Action memory action = _buildAction(AAVE, USDC, 100e6, A_USDC);
        (bool ok, string memory reason) = validator.validate(action, expired);
        assertFalse(ok);
        assertEq(reason, "charter expired");
    }

    function test_validate_passesZeroTokens() public view {
        Action memory action = Action({
            target: AAVE,
            callData: "",
            value: 1 ether,
            tokenIn: address(0),
            amountIn: 0,
            tokenOut: address(0)
        });
        (bool ok,) = validator.validate(action, baseCharter);
        assertTrue(ok);
    }

    function test_validate_passesExactSingleCap() public view {
        Action memory action = _buildAction(AAVE, USDC, 1000e6, A_USDC);
        (bool ok,) = validator.validate(action, baseCharter);
        assertTrue(ok);
    }

    function test_validatePlan_allValid() public view {
        Action[] memory actions = new Action[](2);
        actions[0] = _buildAction(AAVE, USDC, 100e6, A_USDC);
        actions[1] = _buildAction(AAVE, USDC, 200e6, A_USDC);
        (bool ok, uint256 failIdx, string memory reason) = validator.validatePlan(actions, baseCharter);
        assertTrue(ok);
        assertEq(failIdx, 0);
        assertEq(bytes(reason).length, 0);
    }

    function test_validatePlan_failsAtSecondAction() public view {
        Action[] memory actions = new Action[](2);
        actions[0] = _buildAction(AAVE, USDC, 100e6, A_USDC);
        actions[1] = _buildAction(ATTACKER, USDC, 100e6, A_USDC);
        (bool ok, uint256 failIdx, string memory reason) = validator.validatePlan(actions, baseCharter);
        assertFalse(ok);
        assertEq(failIdx, 1);
        assertEq(reason, "target not in charter whitelist");
    }

    function test_validatePlan_emptyPlan() public view {
        Action[] memory actions = new Action[](0);
        (bool ok,,) = validator.validatePlan(actions, baseCharter);
        assertTrue(ok);
    }

    function testFuzz_validate_amountAtOrBelowCap(uint256 amount) public view {
        amount = bound(amount, 0, baseCharter.maxSingleAmountIn);
        Action memory action = _buildAction(AAVE, USDC, amount, A_USDC);
        (bool ok,) = validator.validate(action, baseCharter);
        assertTrue(ok);
    }

    function testFuzz_validate_amountAboveCap(uint256 amount) public view {
        amount = bound(amount, baseCharter.maxSingleAmountIn + 1, type(uint128).max);
        Action memory action = _buildAction(AAVE, USDC, amount, A_USDC);
        (bool ok,) = validator.validate(action, baseCharter);
        assertFalse(ok);
    }

    function _buildAction(address target, address tokenIn, uint256 amountIn, address tokenOut)
        internal
        pure
        returns (Action memory)
    {
        return Action({
            target: target,
            callData: "",
            value: 0,
            tokenIn: tokenIn,
            amountIn: amountIn,
            tokenOut: tokenOut
        });
    }
}
