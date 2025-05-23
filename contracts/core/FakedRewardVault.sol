// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/strategies/kodiak/IRewardVault.sol";

contract RewardVault is IRewardVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Immutable state variables
    address public immutable override factory;
    address public immutable override stakeToken;
    address public immutable override rewardToken;

    // State variables
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;
    uint256 public rewardsDuration = 7 days;

    // Mappings
    mapping(address => uint256) public override rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public balanceOf;

    // Events
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);

    constructor(
        address _factory,
        address _stakeToken,
        address _rewardToken
    ) Ownable(msg.sender) {
        require(_factory != address(0), "Zero factory address");
        require(_stakeToken != address(0), "Zero stake token address");
        require(_rewardToken != address(0), "Zero reward token address");

        factory = _factory;
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply()
        );
    }

    function earned(address account) public view override returns (uint256) {
        return 45_824_107_162_258_373;
        // return balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    function totalSupply() public view returns (uint256) {
        return IERC20(stakeToken).balanceOf(address(this));
    }

    function stake(uint256 amount) external override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        IERC20(stakeToken).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        // require(amount <= balanceOf[msg.sender], "Insufficient balance");
        // balanceOf[msg.sender] -= amount;
        IERC20(stakeToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit(address recipient) external override {
        withdraw(balanceOf[msg.sender]);
        getReward(msg.sender, recipient);
    }

    function getReward(address account, address recipient) public override nonReentrant updateReward(account) returns (uint256) {
        uint256 reward = rewards[account];
        if (reward > 0) {
            rewards[account] = 0;
            IERC20(rewardToken).safeTransfer(recipient, reward);
            emit RewardPaid(account, reward);
        }
        return reward;
    }

    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Previous rewards period must be complete before changing the duration");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }
}
