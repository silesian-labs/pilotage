// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Action, Charter} from "./interfaces/IVault.sol";

contract CharterValidator {
    function validate(Action calldata action, Charter calldata charter)
        external
        view
        returns (bool ok, string memory reason)
    {
        if (!_contains(charter.allowedTargets, action.target)) {
            return (false, "target not in charter whitelist");
        }

        if (action.tokenIn != address(0)) {
            if (!_contains(charter.allowedTokensIn, action.tokenIn)) {
                return (false, "tokenIn not in charter whitelist");
            }
        }

        if (action.tokenOut != address(0)) {
            if (!_contains(charter.allowedTokensOut, action.tokenOut)) {
                return (false, "tokenOut not in charter whitelist");
            }
        }

        if (charter.maxSingleAmountIn > 0 && action.amountIn > charter.maxSingleAmountIn) {
            return (false, "action exceeds maxSingleAmountIn");
        }

        if (charter.expiresAt != 0 && block.timestamp > charter.expiresAt) {
            return (false, "charter expired");
        }

        return (true, "");
    }

    function validatePlan(Action[] calldata actions, Charter calldata charter)
        external
        view
        returns (bool ok, uint256 failIndex, string memory reason)
    {
        for (uint256 i = 0; i < actions.length; i++) {
            (bool actionOk, string memory actionReason) = this.validate(actions[i], charter);
            if (!actionOk) {
                return (false, i, actionReason);
            }
        }
        return (true, 0, "");
    }

    function _contains(address[] calldata list, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == target) return true;
        }
        return false;
    }
}
