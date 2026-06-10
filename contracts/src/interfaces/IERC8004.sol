// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC8004Identity {
    function register(address subject, string calldata metadata) external returns (uint256 identityId);
    function getIdentity(address subject) external view returns (uint256 identityId, string memory metadata);
    function exists(address subject) external view returns (bool);
}

interface IERC8004Reputation {
    function postFeedback(address subject, int256 score, string calldata metadata) external;

    function getScore(address subject) external view returns (int256 score);
    function getFeedbackCount(address subject) external view returns (uint256);
}
