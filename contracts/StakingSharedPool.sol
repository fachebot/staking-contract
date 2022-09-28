// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./StakingContract.sol";

contract StakingSharedPool is Ownable, StakingContract {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    struct PoolInfo {
        uint256 tokenPerBlock;
        uint256 accTokenPerShare;
        uint256 lastRewardBlock;
        uint256 startBlock;
        uint256 endBlock;
    }

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;
    PoolInfo public poolInfo;
    mapping(address => UserInfo) public userInfo;

    event UpdatePool(
        uint256 lastRewardBlock,
        uint256 lpSupply,
        uint256 accTokenPerShare
    );
    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);

    constructor(IERC20 _stakeToken, IERC20 _rewardToken) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
    }

    function newRound(
        uint256 startBlock,
        uint256 endBlock,
        uint256 tokenPerBlock
    ) external onlyOwner {
        require(
            endBlock > startBlock,
            "StakingSharedPool: invalid block range"
        );

        poolInfo.startBlock = startBlock;
        poolInfo.endBlock = endBlock;
        poolInfo.tokenPerBlock = tokenPerBlock;

        uint256 blocks = endBlock - startBlock;
        rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            tokenPerBlock * blocks
        );
    }

    function updatePool() public {
        if (block.number > poolInfo.lastRewardBlock) {
            uint256 lpSupply = stakeToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 blocks = block.number - poolInfo.lastRewardBlock;
                uint256 tokenReward = blocks * poolInfo.tokenPerBlock;
                poolInfo.accTokenPerShare +=
                    (tokenReward * ACC_TOKEN_PRECISION) /
                    lpSupply;
            }

            poolInfo.lastRewardBlock = block.number;
            emit UpdatePool(
                poolInfo.lastRewardBlock,
                lpSupply,
                poolInfo.accTokenPerShare
            );
        }
    }

    function pendingReward(address _user)
        external
        view
        returns (uint256 pending)
    {
        UserInfo storage user = userInfo[_user];
        uint256 accTokenPerShare = poolInfo.accTokenPerShare;
        uint256 lpSupply = stakeToken.balanceOf(address(this));
        if (block.number > poolInfo.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number - poolInfo.lastRewardBlock;
            uint256 tokenReward = blocks * poolInfo.tokenPerBlock;
            accTokenPerShare += (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        pending = (((user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION)
            .toInt256() - user.rewardDebt).toUint256();
    }

    function deposit(uint256 amount, address to) external {
        updatePool();
        UserInfo storage user = userInfo[to];

        user.amount += amount;
        user.rewardDebt += ((amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, to);
    }

    function withdraw(uint256 amount, address to) external {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        user.rewardDebt -= ((amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        stakeToken.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
    }

    function harvest(address to) external {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt = accumulatedToken;

        if (pendingToken != 0) {
            rewardToken.safeTransfer(to, pendingToken);
        }

        emit Harvest(msg.sender, pendingToken);
    }

    function withdrawAndHarvest(uint256 amount, address to) external {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt =
            accumulatedToken -
            ((amount * poolInfo.accTokenPerShare) / ACC_TOKEN_PRECISION)
                .toInt256();
        user.amount -= amount;

        rewardToken.safeTransfer(to, pendingToken);
        stakeToken.safeTransfer(to, amount);

        emit Withdraw(msg.sender, amount, to);
        emit Harvest(msg.sender, pendingToken);
    }
}
