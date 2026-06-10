// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct Action {
    address target;
    bytes callData;
    uint256 value;
    address tokenIn;
    uint256 amountIn;
    address tokenOut;
}

struct VaultState {
    address vault;
    address[] tokens;
    uint256[] balances;
    uint256 totalValueUSD;
}

struct Charter {
    address pilot;
    address[] allowedTargets;
    address[] allowedTokensIn;
    address[] allowedTokensOut;
    uint256 maxSingleAmountIn;
    uint256 maxDailyAmountIn;
    uint256 expiresAt;
}

interface IVault {
    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount, address indexed to);
    event PilotHired(address indexed pilot, uint256 charterExpiry);
    event PilotRevoked(address indexed pilot);
    event ActionExecuted(address indexed pilot, Action action, bool success);
    event Paused();
    event Unpaused();

    function initialize(address owner, address reputation) external;
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount, address to) external;
    function hirePilot(Charter calldata charter) external;
    function revokePilot(address pilot) external;
    function pause() external;
    function unpause() external;
    function forceWithdrawAll(address to, address[] calldata tokens) external;
    function executePlan(Action[] calldata actions) external;
    function captain() external view returns (address);
    function getCharter(address pilot) external view returns (Charter memory);
    function isPaused() external view returns (bool);
}
