// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPilotExecutor} from "./interfaces/IPilotExecutor.sol";
import {Action, VaultState, Charter} from "./interfaces/IVault.sol";
import {IAaveV3Pool} from "./interfaces/IAaveV3Pool.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract ConservativeRWA is IPilotExecutor {
    address public constant AAVE_POOL = 0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff;
    address public constant USDC      = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address public constant A_USDC    = 0x460b97BD498E1157530AEb3086301d5225b91216;

    uint256 public constant DRIFT_THRESHOLD_BPS = 500;
    uint256 public constant MAX_SLIPPAGE_BPS    = 100;

    function riskProfile() external pure override returns (string memory) {
        return "conservative";
    }

    function supportedAssets() external pure override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = USDC;
        assets[1] = A_USDC;
    }

    function validatePlan(Action[] calldata actions, Charter calldata charter)
        external
        pure
        override
        returns (bool)
    {
        for (uint256 i = 0; i < actions.length; i++) {
            if (!_targetAllowed(actions[i].target, charter.allowedTargets)) return false;
            if (actions[i].amountIn > charter.maxSingleAmountIn) return false;
        }
        return true;
    }

    function computeDrifts(uint256[] calldata balances, uint256[] calldata targetsBps)
        external
        pure
        returns (int256[] memory driftsBps)
    {
        require(balances.length == targetsBps.length, "length mismatch");

        uint256 totalValue;
        for (uint256 i = 0; i < balances.length; i++) totalValue += balances[i];

        driftsBps = new int256[](balances.length);
        if (totalValue == 0) return driftsBps;

        for (uint256 i = 0; i < balances.length; i++) {
            uint256 actualBps = (balances[i] * 10_000) / totalValue;
            driftsBps[i] = int256(actualBps) - int256(targetsBps[i]);
        }
    }

    function shouldRebalance(int256[] calldata driftsBps) external pure returns (bool) {
        for (uint256 i = 0; i < driftsBps.length; i++) {
            int256 absDrift = driftsBps[i] < 0 ? -driftsBps[i] : driftsBps[i];
            if (uint256(absDrift) >= DRIFT_THRESHOLD_BPS) return true;
        }
        return false;
    }

    function encodeAaveSupply(address asset, uint256 amount, address onBehalfOf)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IAaveV3Pool.supply.selector, asset, amount, onBehalfOf, 0);
    }

    function encodeAaveWithdraw(address asset, uint256 amount, address to)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, asset, amount, to);
    }

    function _targetAllowed(address target, address[] calldata allowed) internal pure returns (bool) {
        for (uint256 i = 0; i < allowed.length; i++) {
            if (allowed[i] == target) return true;
        }
        return false;
    }
}
