// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public stakingToken;
    address public marketingWallet;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 lockPeriod; // in months (1-12)
        uint256 rewardRate; // monthly reward rate in basis points (500 = 5%)
        bool claimed;
    }

    mapping(address => Stake[]) public stakes;
    mapping(uint256 => bool) public lockPeriodsAllowed;

    uint256 public constant MONTHLY_REWARD_RATE = 500; // 5% per month
    uint256 public constant MAX_LOCK_PERIOD = 12; // 12 months

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, uint256 stakeIndex);
    event Unstaked(address indexed user, uint256 amount, uint256 reward, uint256 stakeIndex);
    event RewardClaimed(address indexed user, uint256 amount, uint256 stakeIndex);

    constructor(address _stakingToken, address _marketingWallet) {
        stakingToken = IERC20(_stakingToken);
        marketingWallet = _marketingWallet;

        // Initialize allowed lock periods (1-12 months)
        for (uint256 i = 1; i <= MAX_LOCK_PERIOD; i++) {
            lockPeriodsAllowed[i] = true;
        }
    }

    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockPeriodsAllowed[lockPeriod], "Invalid lock period");
        require(lockPeriod <= MAX_LOCK_PERIOD, "Lock period exceeds maximum");

        // Transfer tokens from user to this contract
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Create new stake
        stakes[msg.sender].push(Stake({
            amount: amount,
            timestamp: block.timestamp,
            lockPeriod: lockPeriod,
            rewardRate: MONTHLY_REWARD_RATE,
            claimed: false
        }));

        uint256 stakeIndex = stakes[msg.sender].length - 1;
        emit Staked(msg.sender, amount, lockPeriod, stakeIndex);
    }

    function unstake(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(!userStake.claimed, "Stake already claimed");

        uint256 lockTime = userStake.lockPeriod * 30 days;
        require(block.timestamp >= userStake.timestamp.add(lockTime), "Stake is still locked");

        uint256 reward = calculateReward(msg.sender, stakeIndex);
        uint256 totalAmount = userStake.amount.add(reward);

        // Check if marketing wallet has enough tokens for rewards
        require(stakingToken.balanceOf(marketingWallet) >= reward, "Insufficient reward tokens in marketing wallet");

        // Transfer staked amount back to user
        require(stakingToken.transfer(msg.sender, userStake.amount), "Transfer of staked amount failed");

        // Transfer reward from marketing wallet to user
        require(stakingToken.transferFrom(marketingWallet, msg.sender, reward), "Transfer of reward failed");

        // Mark stake as claimed
        userStake.claimed = true;

        emit Unstaked(msg.sender, userStake.amount, reward, stakeIndex);
    }

    function claimReward(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(!userStake.claimed, "Stake already claimed");

        uint256 reward = calculateReward(msg.sender, stakeIndex);

        // Check if marketing wallet has enough tokens for rewards
        require(stakingToken.balanceOf(marketingWallet) >= reward, "Insufficient reward tokens in marketing wallet");

        // Transfer reward from marketing wallet to user
        require(stakingToken.transferFrom(marketingWallet, msg.sender, reward), "Transfer of reward failed");

        emit RewardClaimed(msg.sender, reward, stakeIndex);
    }

    function calculateReward(address user, uint256 stakeIndex) public view returns (uint256) {
        require(stakeIndex < stakes[user].length, "Invalid stake index");
        Stake memory userStake = stakes[user][stakeIndex];

        uint256 lockTime = userStake.lockPeriod * 30 days;
        uint256 elapsed = block.timestamp > userStake.timestamp.add(lockTime) 
            ? lockTime 
            : block.timestamp.sub(userStake.timestamp);
        
        uint256 monthsElapsed = elapsed.div(30 days);
        return userStake.amount.mul(monthsElapsed).mul(userStake.rewardRate).div(10000);
    }

    function getStakesCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    function setMarketingWallet(address _marketingWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
    }

    function setLockPeriodAllowed(uint256 lockPeriod, bool allowed) external onlyOwner {
        require(lockPeriod > 0 && lockPeriod <= MAX_LOCK_PERIOD, "Invalid lock period");
        lockPeriodsAllowed[lockPeriod] = allowed;
    }

    function setMonthlyRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= 2000, "Reward rate cannot exceed 20%");
        // Note: This only affects new stakes, existing stakes keep their original rate
    }
}
