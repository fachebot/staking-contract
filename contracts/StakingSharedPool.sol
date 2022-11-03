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

    uint64 startBlock;
    uint64 endBlock;
    uint128 tokenPerBlock;
    uint256 accTokenPerShare;
    uint256 lastRewardBlock;
    mapping(address => UserInfo) userInfo;

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event AddPeriod(uint64 startBlock, uint64 endBlock, uint128 tokenPerBlock);
    event UpdatePool(
        uint256 lastRewardBlock,
        uint256 supply,
        uint256 accTokenPerShare
    );
    event Stake(address indexed user, uint256 amount, address indexed to);
    event Unstake(address indexed user, uint256 amount, address indexed to);
    event Claim(address indexed user, uint256 amount);

    constructor(IERC20 _stakeToken, IERC20 _rewardToken) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
    }

    /// @notice Add a new reward period.
    /// @param _startBlock Block number of start distributing rewards.
    /// @param _endBlock Block number of stop distributing rewards.
    /// @param _tokenPerBlock Amount of reward tokens per block.
    function addPeriod(
        uint64 _startBlock,
        uint64 _endBlock,
        uint128 _tokenPerBlock
    ) external onlyOwner {
        require(
            _endBlock > _startBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            _startBlock > endBlock,
            "StakingSharedPool: invalid block range"
        );
        require(
            block.number > endBlock,
            "StakingSharedPool: previous period did not end"
        );

        updatePool();

        startBlock = _startBlock;
        endBlock = _endBlock;
        tokenPerBlock = _tokenPerBlock;
        lastRewardBlock = _startBlock;

        rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            tokenPerBlock * (endBlock - startBlock)
        );

        emit AddPeriod(startBlock, endBlock, tokenPerBlock);
    }

    /// @notice View function to see pending reward token on frontend.
    /// @param _user Address of user.
    /// @return pending Token reward for a given user.
    function pendingReward(address _user) external view returns (uint256) {
        uint256 value = accTokenPerShare;
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = stakeToken.balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint256 reward = blocksReward();
            value += (reward * ACC_TOKEN_PRECISION) / lpSupply;
        }

        return
            (((user.amount * value) / ACC_TOKEN_PRECISION).toInt256() -
                user.rewardDebt).toUint256();
    }

    /// @notice Calculates and returns the `amount` of reward token.
    function blocksReward() internal view returns (uint256) {
        uint256 end = block.number < endBlock ? block.number : endBlock;
        uint256 start = lastRewardBlock >= startBlock
            ? lastRewardBlock
            : startBlock;

        return end <= start ? 0 : (end - start) * tokenPerBlock;
    }

    /// @notice Update reward variables of the given pool.
    function updatePool() public {
        if (block.number > lastRewardBlock) {
            uint256 lpSupply = stakeToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 reward = blocksReward();
                accTokenPerShare += (reward * ACC_TOKEN_PRECISION) / lpSupply;
            }

            lastRewardBlock = block.number;
            emit UpdatePool(lastRewardBlock, lpSupply, accTokenPerShare);
        }
    }

    /// @notice Deposit stake tokens to contract for reward allocation.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function stake(uint256 amount, address to) external {
        updatePool();

        UserInfo storage user = userInfo[to];
        user.amount += amount;
        user.rewardDebt += ((amount * accTokenPerShare) / ACC_TOKEN_PRECISION)
            .toInt256();

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, amount, to);
    }

    /// @notice Withdraw stake token from contract.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function unstake(uint256 amount, address to) external {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        user.rewardDebt -= ((amount * accTokenPerShare) / ACC_TOKEN_PRECISION)
            .toInt256();
        user.amount -= amount;

        stakeToken.safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, to);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param to Receiver of SUSHI rewards.
    function claim(address to) external {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount * accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt = accumulatedToken;

        if (pendingToken > 0) {
            rewardToken.safeTransfer(to, pendingToken);
        }

        emit Claim(msg.sender, pendingToken);
    }

    /// @notice Withdraw stake token from contract and claim proceeds for transaction sender to `to`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SUSHI rewards.
    function unstakeAndClaim(uint256 amount, address to) external {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedToken = ((user.amount * accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt =
            accumulatedToken -
            ((amount * accTokenPerShare) / ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        rewardToken.safeTransfer(to, pendingToken);
        stakeToken.safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, to);
        emit Claim(msg.sender, pendingToken);
    }
}
