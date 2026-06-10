// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";
import {IPilotExecutor} from "./interfaces/IPilotExecutor.sol";

struct PilotCard {
    string name;
    string description;
    string riskProfile;
    string ipfsMetadata;
    address[] supportedChains;
}

struct PilotRecord {
    uint256 id;
    address developer;
    address executor;
    address operator;
    PilotCard card;
    uint256 stakedAmount;
    bool active;
    bool slashed;
    uint256 registeredAt;
}

contract PilotRegistry {
    address public immutable stakeToken;
    address public owner;
    uint256 public minStake;

    uint256 private _nextId;
    mapping(uint256 id => PilotRecord) private _pilots;
    mapping(address developer => uint256[] ids) private _developerPilots;
    mapping(address executor => uint256 id) public executorToPilotId;

    uint256[] private _activePilotIds;
    mapping(uint256 id => uint256 index) private _activeIndex;

    event PilotRegistered(uint256 indexed id, address indexed developer, address indexed executor, address operator, string name);
    event PilotUpdated(uint256 indexed id);
    event PilotUnregistered(uint256 indexed id);
    event PilotSlashed(uint256 indexed id, string reason);
    event MinStakeUpdated(uint256 newMinStake);

    error NotOwner();
    error NotDeveloper();
    error PilotNotActive();
    error InsufficientStake();
    error AlreadySlashed();
    error ExecutorAlreadyRegistered();
    error ZeroAddress();

    constructor(address _stakeToken, uint256 _minStake) {
        if (_stakeToken == address(0)) revert ZeroAddress();
        stakeToken = _stakeToken;
        minStake = _minStake;
        owner = msg.sender;
        _nextId = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function registerPilot(PilotCard calldata card, address executor, address operator, uint256 stake)
        external
        returns (uint256 id)
    {
        if (executor == address(0) || operator == address(0)) revert ZeroAddress();
        if (executorToPilotId[executor] != 0) revert ExecutorAlreadyRegistered();
        if (stake < minStake) revert InsufficientStake();

        IERC20(stakeToken).transferFrom(msg.sender, address(this), stake);

        id = _nextId++;

        _pilots[id] = PilotRecord({
            id: id,
            developer: msg.sender,
            executor: executor,
            operator: operator,
            card: card,
            stakedAmount: stake,
            active: true,
            slashed: false,
            registeredAt: block.timestamp
        });

        _developerPilots[msg.sender].push(id);
        executorToPilotId[executor] = id;

        _activePilotIds.push(id);
        _activeIndex[id] = _activePilotIds.length - 1;

        emit PilotRegistered(id, msg.sender, executor, operator, card.name);
    }

    function updatePilotCard(uint256 id, PilotCard calldata card) external {
        if (_pilots[id].developer != msg.sender) revert NotDeveloper();
        if (!_pilots[id].active) revert PilotNotActive();
        _pilots[id].card = card;
        emit PilotUpdated(id);
    }

    function unregisterPilot(uint256 id) external {
        PilotRecord storage p = _pilots[id];
        if (p.developer != msg.sender) revert NotDeveloper();
        if (!p.active) revert PilotNotActive();

        p.active = false;
        _removeFromActive(id);

        if (!p.slashed) {
            IERC20(stakeToken).transfer(msg.sender, p.stakedAmount);
        }

        emit PilotUnregistered(id);
    }

    function slashPilot(uint256 id, string calldata reason) external onlyOwner {
        PilotRecord storage p = _pilots[id];
        if (p.slashed) revert AlreadySlashed();

        p.slashed = true;
        p.active = false;
        _removeFromActive(id);

        IERC20(stakeToken).transfer(owner, p.stakedAmount);

        emit PilotSlashed(id, reason);
    }

    function setMinStake(uint256 newMinStake) external onlyOwner {
        minStake = newMinStake;
        emit MinStakeUpdated(newMinStake);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function getPilot(uint256 id) external view returns (PilotRecord memory) {
        return _pilots[id];
    }

    function activePilotCount() external view returns (uint256) {
        return _activePilotIds.length;
    }

    function getActivePilotIds(uint256 start, uint256 limit)
        external
        view
        returns (uint256[] memory ids)
    {
        uint256 end = start + limit > _activePilotIds.length ? _activePilotIds.length : start + limit;
        ids = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            ids[i - start] = _activePilotIds[i];
        }
    }

    function getDeveloperPilots(address developer) external view returns (uint256[] memory) {
        return _developerPilots[developer];
    }

    function _removeFromActive(uint256 id) internal {
        uint256 idx = _activeIndex[id];
        uint256 last = _activePilotIds[_activePilotIds.length - 1];
        _activePilotIds[idx] = last;
        _activeIndex[last] = idx;
        _activePilotIds.pop();
        delete _activeIndex[id];
    }
}
