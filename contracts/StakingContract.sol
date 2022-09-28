// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface StakingContract {
    function deposit(uint256 amount, address to) external;
    function withdraw(uint256 amount, address to) external;
    function harvest(address to) external;
    function withdrawAndHarvest(uint256 amount, address to) external;
    function pendingReward(address user) external view returns(uint256);
}