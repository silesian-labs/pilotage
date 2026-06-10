// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockERC8004Reputation {
    mapping(address subject => int256 score) public scoreOf;
    mapping(address subject => uint256 count) public feedbackCount;

    event FeedbackPosted(address indexed subject, int256 score, string metadata);

    function postFeedback(address subject, int256 score, string calldata metadata) external {
        scoreOf[subject] += score;
        feedbackCount[subject] += 1;
        emit FeedbackPosted(subject, score, metadata);
    }

    function getScore(address subject) external view returns (int256) {
        return scoreOf[subject];
    }

    function getFeedbackCount(address subject) external view returns (uint256) {
        return feedbackCount[subject];
    }
}
