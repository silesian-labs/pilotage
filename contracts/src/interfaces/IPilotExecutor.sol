// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Action, VaultState, Charter} from "./IVault.sol";

interface IPilotExecutor {
    function riskProfile() external view returns (string memory);

    function supportedAssets() external view returns (address[] memory);

    function validatePlan(Action[] calldata actions, Charter calldata charter) external view returns (bool);
}
