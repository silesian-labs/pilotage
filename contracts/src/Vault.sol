// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault, Action, Charter} from "./interfaces/IVault.sol";
import {CharterValidator} from "./CharterValidator.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC8004Reputation} from "./interfaces/IERC8004.sol";

contract Vault is IVault {
    address public captain;
    bool private _paused;
    bool private _initialized;
    bool private _locked;

    CharterValidator public validator;

    address public reputation;

    mapping(address pilot => Charter) private _charters;
    mapping(address pilot => bool) private _hasCharter;
    mapping(address pilot => uint256 dayStart) private _pilotDayStart;
    mapping(address pilot => uint256 spent) private _pilotDailySpent;

    error NotCaptain();
    error AlreadyInitialized();
    error AlreadyPaused();
    error NotCurrentlyPaused();
    error NoPilotCharter();
    error CharterExpired();
    error ValidationFailed(string reason);
    error ActionFailed(uint256 index);
    error DailyLimitExceeded();
    error TokenOutNotReceived(uint256 index);
    error TokenOutRequiredWhenSpending(uint256 index);
    error EthValueNotAllowed(uint256 index);
    error Reentrancy();
    error ZeroAddress();
    error ZeroAmount();

    modifier onlyCaptain() {
        if (msg.sender != captain) revert NotCaptain();
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert AlreadyPaused();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    function initialize(address _captain, address _reputation) external {
        if (_initialized) revert AlreadyInitialized();
        if (_captain == address(0)) revert ZeroAddress();
        _initialized = true;
        captain = _captain;
        reputation = _reputation;
        validator = new CharterValidator();
    }

    function deposit(address token, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Deposited(token, amount);
    }

    function withdraw(address token, uint256 amount, address to) external onlyCaptain {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).transfer(to, amount);
        emit Withdrawn(token, amount, to);
    }

    function hirePilot(Charter calldata charter) external onlyCaptain {
        if (charter.pilot == address(0)) revert ZeroAddress();
        _charters[charter.pilot] = charter;
        _hasCharter[charter.pilot] = true;
        emit PilotHired(charter.pilot, charter.expiresAt);
    }

    function revokePilot(address pilot) external onlyCaptain {
        _hasCharter[pilot] = false;
        delete _charters[pilot];
        emit PilotRevoked(pilot);
    }

    function pause() external onlyCaptain {
        if (_paused) revert AlreadyPaused();
        _paused = true;
        emit Paused();
    }

    function unpause() external onlyCaptain {
        if (!_paused) revert NotCurrentlyPaused();
        _paused = false;
        emit Unpaused();
    }

    function forceWithdrawAll(address to, address[] calldata tokens) external onlyCaptain {
        if (to == address(0)) revert ZeroAddress();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 bal = IERC20(tokens[i]).balanceOf(address(this));
            if (bal > 0) {
                IERC20(tokens[i]).transfer(to, bal);
                emit Withdrawn(tokens[i], bal, to);
            }
        }
    }

    function executePlan(Action[] calldata actions) external whenNotPaused nonReentrant {
        if (!_hasCharter[msg.sender]) revert NoPilotCharter();

        Charter storage charter = _charters[msg.sender];

        if (charter.expiresAt != 0 && block.timestamp > charter.expiresAt) revert CharterExpired();

        if (block.timestamp >= _pilotDayStart[msg.sender] + 1 days) {
            _pilotDayStart[msg.sender] = block.timestamp;
            _pilotDailySpent[msg.sender] = 0;
        }

        uint256 totalSpentThisTx;

        for (uint256 i = 0; i < actions.length; i++) {
            Action calldata action = actions[i];

            (bool ok, string memory reason) = validator.validate(action, charter);
            if (!ok) revert ValidationFailed(reason);

            if (action.value != 0) revert EthValueNotAllowed(i);

            totalSpentThisTx += action.amountIn;

            if (action.tokenIn != address(0) && action.amountIn > 0 && action.tokenOut == address(0)) {
                revert TokenOutRequiredWhenSpending(i);
            }

            uint256 tokenOutBefore = (action.tokenOut != address(0))
                ? IERC20(action.tokenOut).balanceOf(address(this))
                : 0;

            if (action.tokenIn != address(0) && action.amountIn > 0) {
                IERC20(action.tokenIn).approve(action.target, action.amountIn);
            }

            (bool success,) = action.target.call(action.callData);
            if (!success) revert ActionFailed(i);

            if (action.tokenIn != address(0)) {
                IERC20(action.tokenIn).approve(action.target, 0);
            }

            if (action.tokenOut != address(0)) {
                uint256 tokenOutAfter = IERC20(action.tokenOut).balanceOf(address(this));
                if (tokenOutAfter <= tokenOutBefore) revert TokenOutNotReceived(i);
            }

            emit ActionExecuted(msg.sender, action, true);
        }

        uint256 newDailyTotal = _pilotDailySpent[msg.sender] + totalSpentThisTx;
        if (charter.maxDailyAmountIn > 0 && newDailyTotal > charter.maxDailyAmountIn) {
            revert DailyLimitExceeded();
        }
        _pilotDailySpent[msg.sender] = newDailyTotal;

        if (reputation != address(0) && actions.length > 0) {
            try IERC8004Reputation(reputation).postFeedback(msg.sender, int256(1), "safe passage") {} catch {}
        }
    }

    function getCharter(address pilot) external view returns (Charter memory) {
        return _charters[pilot];
    }

    function isPaused() external view returns (bool) {
        return _paused;
    }

    function getDailySpent(address pilot) external view returns (uint256) {
        if (block.timestamp >= _pilotDayStart[pilot] + 1 days) return 0;
        return _pilotDailySpent[pilot];
    }
}
