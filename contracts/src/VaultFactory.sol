// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vault} from "./Vault.sol";
import {Clones} from "./lib/Clones.sol";

contract VaultFactory {
    using Clones for address;

    address public immutable vaultImplementation;
    address public immutable reputationRegistry;

    mapping(address captain => address vault) public vaultOf;
    address[] private _allVaults;

    event VaultCreated(address indexed captain, address indexed vault, uint256 timestamp);

    error VaultAlreadyExists();

    constructor(address _reputationRegistry) {
        reputationRegistry = _reputationRegistry;
        vaultImplementation = address(new Vault());
    }

    function createVault() external returns (address vault) {
        if (vaultOf[msg.sender] != address(0)) revert VaultAlreadyExists();

        vault = vaultImplementation.clone();
        Vault(payable(vault)).initialize(msg.sender, reputationRegistry);

        vaultOf[msg.sender] = vault;
        _allVaults.push(vault);

        emit VaultCreated(msg.sender, vault, block.timestamp);
    }

    function allVaultsCount() external view returns (uint256) {
        return _allVaults.length;
    }

    function allVaults(uint256 start, uint256 limit) external view returns (address[] memory result) {
        uint256 end = start + limit > _allVaults.length ? _allVaults.length : start + limit;
        result = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = _allVaults[i];
        }
    }
}
