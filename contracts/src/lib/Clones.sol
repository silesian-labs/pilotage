// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Clones {
    error CloneDeployFailed();

    function clone(address implementation) internal returns (address instance) {
        assembly {
            mstore(0x00, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(0x14, shl(0x60, implementation))
            mstore(0x28, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, 0x00, 0x37)
        }
        if (instance == address(0)) revert CloneDeployFailed();
    }
}
