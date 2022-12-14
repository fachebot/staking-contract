// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingSharedPoolL2 is Ownable, Pausable {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint128 accTokenPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
        uint256 totalStaked;
    }

    uint64 public startBlock;
    uint64 public endBlock;
    uint128 public tokenPerBlock;
    uint256 public totalAllocPoint;

    PoolInfo[] public poolInfo;
    IERC20[] public stakeToken;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    IERC20 public immutable rewardToken;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event Stake(address indexed user, uint256 amount, address indexed to);
    event Unstake(address indexed user, uint256 amount, address indexed to);
    event Claim(address indexed user, uint256 amount);

    event AddPool(uint256 indexed pid, uint256 allocPoint, IERC20 indexed stakeToken);
    event SetPool(uint256 indexed pid, uint256 allocPoint);
    event UpdatePool(uint256 lastRewardBlock, uint256 supply, uint256 accTokenPerShare);
    event AddPeriod(uint64 startBlock, uint64 endBlock, uint128 tokenPerBlock);

    constructor(IERC20 _rewardToken) {
        rewardToken = _rewardToken;
    }

    /// @notice Returns the number of contract pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Triggers stopped state.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice  Returns to normal state.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Add a new stake token to the pool. Can only be called by the owner.
    /// DO NOT add the same stake token more than once. Rewards will be messed up if you do.
    /// @param _allocPoint AP of the new pool.
    /// @param _stakeToken Address of the stake ERC-20 token.
    function add(uint256 _allocPoint, IERC20 _stakeToken) public onlyOwner {
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint + _allocPoint;

        stakeToken.push(_stakeToken);
        poolInfo.push(
            PoolInfo({
                allocPoint: _allocPoint.toUint64(),
                lastRewardBlock: lastRewardBlock.toUint64(),
                accTokenPerShare: 0,
                totalStaked: 0
            })
        );

        emit AddPool(stakeToken.length - 1, _allocPoint, _stakeToken);
    }

    /// @notice Update the given pool's reward token allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint.toUint64();

        emit SetPool(_pid, _allocPoint);
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
            "StakingSharedPoolL2: invalid block range"
        );
        require(
            _startBlock > endBlock,
            "StakingSharedPoolL2: invalid block range"
        );
        require(
            block.number > endBlock,
            "StakingSharedPoolL2: previous period did not end"
        );

        uint256 size = poolLength();
        for (uint256 pid = 0; pid < size; pid++) {
            updatePool(pid);
            poolInfo[pid].lastRewardBlock = _startBlock;
        }

        startBlock = _startBlock;
        endBlock = _endBlock;
        tokenPerBlock = _tokenPerBlock;

        rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            tokenPerBlock * (endBlock - startBlock)
        );

        emit AddPeriod(startBlock, endBlock, tokenPerBlock);
    }

    /// @notice View function to see pending reward token on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending Token reward for a given user.
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        uint256 accTokenPerShare = poolInfo[_pid].accTokenPerShare;
        UserInfo storage user = userInfo[_pid][_user];
        if (
            block.number > poolInfo[_pid].lastRewardBlock &&
            poolInfo[_pid].totalStaked != 0
        ) {
            uint256 reward = blocksReward(_pid);
            accTokenPerShare +=
                (reward * ACC_TOKEN_PRECISION) /
                poolInfo[_pid].totalStaked;
        }

        return
            (((user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION)
                .toInt256() - user.rewardDebt).toUint256();
    }

    /// @notice Calculates and returns the `amount` of reward token.
    /// @param pid The index of the pool. See `poolInfo`.
    function blocksReward(uint256 pid) internal view returns (uint256) {
        PoolInfo memory pool = poolInfo[pid];
        uint256 end = block.number < endBlock ? block.number : endBlock;
        uint256 start = pool.lastRewardBlock >= startBlock
            ? pool.lastRewardBlock
            : startBlock;

        uint256 blocks = end <= start ? 0 : (end - start);
        return (blocks * tokenPerBlock * pool.allocPoint) / totalAllocPoint;
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            if (pool.totalStaked > 0) {
                uint256 reward = blocksReward(pid);
                pool.accTokenPerShare += ((reward * ACC_TOKEN_PRECISION) /
                    pool.totalStaked).toUint128();
            }

            pool.lastRewardBlock = block.number.toUint64();
            poolInfo[pid] = pool;

            emit UpdatePool(block.number, pool.totalStaked, pool.accTokenPerShare);
        }
    }

    /// @notice Deposit stake tokens to contract for reward allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function stake(
        uint256 pid,
        uint256 amount,
        address to
    ) external whenNotPaused {
        PoolInfo memory pool = updatePool(pid);

        UserInfo storage user = userInfo[pid][to];
        user.amount += amount;
        user.rewardDebt += ((amount * pool.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();

        poolInfo[pid].totalStaked += amount;

        stakeToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, amount, to);
    }

    /// @notice Withdraw stake token from contract.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function unstake(
        uint256 pid,
        uint256 amount,
        address to
    ) external whenNotPaused {
        PoolInfo memory pool = updatePool(pid);

        UserInfo storage user = userInfo[pid][msg.sender];
        user.rewardDebt -= ((amount * pool.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        poolInfo[pid].totalStaked -= amount;

        stakeToken[pid].safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, to);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SUSHI rewards.
    function claim(uint256 pid, address to) external whenNotPaused {
        PoolInfo memory pool = updatePool(pid);

        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedToken = ((user.amount * pool.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt = accumulatedToken;

        if (pendingToken > 0) {
            rewardToken.safeTransfer(to, pendingToken);
        }

        emit Claim(msg.sender, pendingToken);
    }

    /// @notice Withdraw stake token from contract and claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SUSHI rewards.
    function unstakeAndClaim(
        uint256 pid,
        uint256 amount,
        address to
    ) external whenNotPaused {
        PoolInfo memory pool = updatePool(pid);

        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedToken = ((user.amount * pool.accTokenPerShare) /
            ACC_TOKEN_PRECISION).toInt256();
        uint256 pendingToken = (accumulatedToken - user.rewardDebt).toUint256();

        user.rewardDebt =
            accumulatedToken -
            ((amount * pool.accTokenPerShare) / ACC_TOKEN_PRECISION).toInt256();
        user.amount -= amount;

        poolInfo[pid].totalStaked -= amount;

        rewardToken.safeTransfer(to, pendingToken);
        stakeToken[pid].safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, to);
        emit Claim(msg.sender, pendingToken);
    }

    /// @notice Destroy contract and withdraw all funds to owner.
    function kill() external onlyOwner {
        uint256 size = poolLength();
        for (uint256 pid = 0; pid < size; pid++) {
            uint256 v = stakeToken[pid].balanceOf(address(this));
            if (v > 0) {
                stakeToken[pid].safeTransfer(owner(), v);
            }
        }

        uint256 balance = rewardToken.balanceOf(address(this));
        if (balance > 0) {
            rewardToken.safeTransfer(owner(), balance);
        }

        selfdestruct(payable(owner()));
    }
}
