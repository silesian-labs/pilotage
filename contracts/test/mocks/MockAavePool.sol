// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MockAavePool {
    MockERC20 public immutable aToken;

    mapping(address user => uint256 supplied) public supplied;

    function supplied_set(address user, uint256 amount) external {
        supplied[user] = amount;
    }

    event Supplied(address indexed asset, uint256 amount, address indexed onBehalfOf);
    event Withdrawn(address indexed asset, uint256 amount, address indexed to);

    constructor() {
        aToken = new MockERC20("Mock aUSDC", "aUSDC", 6);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
        supplied[onBehalfOf] += amount;
        emit Supplied(asset, amount, onBehalfOf);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(supplied[msg.sender] >= amount, "insufficient supplied");
        supplied[msg.sender] -= amount;
        IERC20(asset).transfer(to, amount);
        emit Withdrawn(asset, amount, to);
        return amount;
    }

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        totalCollateralBase = supplied[user] * 1e12;
        totalDebtBase = 0;
        availableBorrowsBase = 0;
        currentLiquidationThreshold = 0;
        ltv = 0;
        healthFactor = type(uint256).max;
    }
}
