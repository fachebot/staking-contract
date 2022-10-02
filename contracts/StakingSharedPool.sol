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
        IERC20 stakeToken;
        IERC20 rewardToken;
        uint64 startBlock;
        uint64 endBlock;
        uint128 tokenPerBlock;
        uint256 accTokenPerShare;
        uint256 lastRewardBlock;
        mapping(address => UserInfo) userInfo;
    }

    uint256 public next;
    mapping(uint256 => PoolInfo) public poolInfo;

    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event NewPool(uint256 pid, IERC20 stakeToken, IERC20 rewardToken);
    event NewPeriod(
        uint256 pid,
        uint64 startBlock,
        uint64 endBlock,
        uint128 tokenPerBlock
    );
    event UpdatePool(
        uint256 pid,
        uint256 lastRewardBlock,
        uint256 lpSupply,
        uint256 accTokenPerShare
    );
    event Stake(
        uint256 pid,
        address indexed user,
        uint256 amount,
        address indexed to
    );
    event Unstake(
        uint256 pid,
        address indexed user,
        uint256 amount,
        address indexed to
    );
    event Claim(uint256 pid, address indexed user, uint256 amount);

    function newPool(IERC20 stakeToken, IERC20 rewardToken)
        external
        returns (uint256)
    {
        uint256 pid = next;
        next++;

        poolInfo[pid].stakeToken = stakeToken;
        poolInfo[pid].rewardToken = rewardToken;

        emit NewPool(pid, stakeToken, rewardToken);

        return pid;
    }

    function newPeriod(
        uint256 pid,
        uint64 startBlock,
        uint64 endBlock,
        uint128 tokenPerBlock
    ) external onlyOwner {
        require(
            endBlock > startBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            startBlock > poolInfo[pid].endBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            block.number > poolInfo[pid].endBlock,
            "StakingSharedPool: previous period did not end"
        );

        updatePool(pid);

        poolInfo[pid].startBlock = startBlock;
        poolInfo[pid].endBlock = endBlock;
        poolInfo[pid].tokenPerBlock = tokenPerBlock;
        poolInfo[pid].lastRewardBlock = startBlock;

        poolInfo[pid].rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            tokenPerBlock * (endBlock - startBlock)
        );

        emit NewPeriod(pid, startBlock, endBlock, tokenPerBlock);
    }

    function pendingReward(uint256 pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[pid];
        require(
            address(pool.stakeToken) != address(0),
            "StakingSharedPool: pool not found"
        );

        uint256 value = pool.accTokenPerShare;
        UserInfo storage user = pool.userInfo[_user];
        uint256 lpSupply = pool.stakeToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 tokenReward = blocksReward(pid);
            value += (tokenReward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        return
            (((user.amount * value) / ACC_TOKEN_PRECISION).toInt256() -
                user.rewardDebt).toUint256();
    }

    function blocksReward(uint256 pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        require(
            address(pool.stakeToken) != address(0),
            "StakingSharedPool: pool not found"
        );

        uint256 end = block.number < pool.endBlock
            ? block.number
            : pool.endBlock;
        uint256 start = pool.lastRewardBlock >= pool.startBlock
            ? pool.lastRewardBlock
            : pool.startBlock;

        return end <= start ? 0 : (end - start) * pool.tokenPerBlock;
    }

    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        require(
            address(pool.stakeToken) != address(0),
            "StakingSharedPool: pool not found"
        );

        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = pool.stakeToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 tokenReward = blocksReward(pid);
                pool.accTokenPerShare +=
                    (tokenReward * ACC_TOKEN_PRECISION) /
                    lpSupply;
            }

            pool.lastRewardBlock = block.number;
            emit UpdatePool(
                pid,
                pool.lastRewardBlock,
                lpSupply,
                pool.accTokenPerShare
            );
        }
    }

    function stake(
        uint256 pid,
        uint256 amount,
        address to
    ) external {
        updatePool(pid);
        UserInfo storage user = poolInfo[pid].userInfo[to];

        user.amount += amount;
        user.rewardDebt += ((amount * poolInfo[pid].accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();

        poolInfo[pid].stakeToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit Stake(pid, msg.sender, amount, to);
    }

    function unstake(
        uint256 pid,
        uint256 amount,
        address to
    ) external {
        updatePool(pid);

        UserInfo storage user = poolInfo[pid].userInfo[msg.sender];
        user.rewardDebt -= ((amount * poolInfo[pid].accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        poolInfo[pid].stakeToken.safeTransfer(to, amount);

        emit Unstake(pid, msg.sender, amount, to);
    }

    function claim(uint256 pid, address to) external {
        updatePool(pid);

        UserInfo storage user = poolInfo[pid].userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount *
            poolInfo[pid].accTokenPerShare) / ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt = accumulatedToken;

        if (pendingToken > 0) {
            poolInfo[pid].rewardToken.safeTransfer(to, pendingToken);
        }

        emit Claim(pid, msg.sender, pendingToken);
    }

    function unstakeAndClaim(
        uint256 pid,
        uint256 amount,
        address to
    ) external {
        updatePool(pid);

        UserInfo storage user = poolInfo[pid].userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount *
            poolInfo[pid].accTokenPerShare) / ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt =
            accumulatedToken -
            ((amount * poolInfo[pid].accTokenPerShare) / ACC_TOKEN_PRECISION)
                .toInt256();
        user.amount -= amount;

        poolInfo[pid].rewardToken.safeTransfer(to, pendingToken);
        poolInfo[pid].stakeToken.safeTransfer(to, amount);

        emit Unstake(pid, msg.sender, amount, to);
        emit Claim(pid, msg.sender, pendingToken);
    }
}
