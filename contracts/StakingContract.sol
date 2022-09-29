// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface StakingContract {
    function stake(uint256 amount, address to) external;
    function unstake(uint256 amount, address to) external;
    function claim(address to) external;
    function unstakeAndClaim(uint256 amount, address to) external;
    function pendingReward(address user) external view returns(uint256);
}