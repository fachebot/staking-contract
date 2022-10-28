// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingSharedPool is Ownable {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint64 startBlock;
        uint64 endBlock;
        uint128 tokenPerBlock;
        uint256 accTokenPerShare;
        uint256 lastRewardBlock;
        mapping(address => UserInfo) userInfo;
    }

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    PoolInfo public poolInfo;

    event AddPeriod(uint64 startBlock, uint64 endBlock, uint128 tokenPerBlock);
    event UpdatePool(uint256 lastRewardBlock, uint256 lpSupply, uint256 accTokenPerShare);
    event Stake(address indexed user, uint256 amount, address indexed to);
    event Unstake(address indexed user, uint256 amount, address indexed to);
    event Claim(address indexed user, uint256 amount);

    constructor(IERC20 _stakeToken, IERC20 _rewardToken) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
    }

    function addPeriod(
        uint64 startBlock,
        uint64 endBlock,
        uint128 tokenPerBlock
    ) external onlyOwner {
        require(
            endBlock > startBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            startBlock > poolInfo.endBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            block.number > poolInfo.endBlock,
            "StakingSharedPool: previous period did not end"
        );

        updatePool();

        poolInfo.startBlock = startBlock;
        poolInfo.endBlock = endBlock;
        poolInfo.tokenPerBlock = tokenPerBlock;
        poolInfo.lastRewardBlock = startBlock;

        rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            tokenPerBlock * (endBlock - startBlock)
        );

        emit AddPeriod(startBlock, endBlock, tokenPerBlock);
    }

    function pendingReward(address _user)
        external
        view
        returns (uint256)
    {
        uint256 value = poolInfo.accTokenPerShare;
        UserInfo storage user = poolInfo.userInfo[_user];
        uint256 lpSupply = stakeToken.balanceOf(address(this));
        if (block.number > poolInfo.lastRewardBlock && lpSupply != 0) {
            uint256 tokenReward = blocksReward();
            value += (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        return
            (((user.amount * value) / ACC_TOKEN_PRECISION).toInt256() -
                user.rewardDebt).toUint256();
    }

    function blocksReward() internal view returns (uint256) {
        uint256 end = block.number < poolInfo.endBlock
            ? block.number
            : poolInfo.endBlock;
        uint256 start = poolInfo.lastRewardBlock >= poolInfo.startBlock
            ? poolInfo.lastRewardBlock
            : poolInfo.startBlock;

        return end <= start ? 0 : (end - start) * poolInfo.tokenPerBlock;
    }

    function updatePool() public {
        if (block.number > poolInfo.lastRewardBlock) {
            uint256 lpSupply = stakeToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 tokenReward = blocksReward();
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

    function stake(
        uint256 amount,
        address to
    ) external {
        updatePool();

        UserInfo storage user = poolInfo.userInfo[to];
        user.amount += amount;
        user.rewardDebt += ((amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, amount, to);
    }

    function unstake(
        uint256 amount,
        address to
    ) external {
        updatePool();

        UserInfo storage user = poolInfo.userInfo[msg.sender];
        user.rewardDebt -= ((amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        stakeToken.safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, to);
    }

    function claim(address to) external {
        updatePool();

        UserInfo storage user = poolInfo.userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount * poolInfo.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt = accumulatedToken;

        if (pendingToken > 0) {
            rewardToken.safeTransfer(to, pendingToken);
        }

        emit Claim(msg.sender, pendingToken);
    }

    function unstakeAndClaim(
        uint256 amount,
        address to
    ) external {
        updatePool();

        UserInfo storage user = poolInfo.userInfo[msg.sender];
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

        emit Unstake(msg.sender, amount, to);
        emit Claim(msg.sender, pendingToken);
    }
}
