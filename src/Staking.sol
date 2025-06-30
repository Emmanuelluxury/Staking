// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking {
    IERC20 public rewardToken;
    address public owner;
    uint256 public rewardRate;
    uint256 public maturityPeriod;
    uint256 public totalStaked;
    uint256 public totalWithdrawals;
    uint256 public totalRewardsClaimed;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        bool withdrawn;
        bool claimed;
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 reward);
    event Withdrawn(address indexed user, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardRateUpdated(uint256 newRate);
    event MaturityPeriodUpdated(uint256 newPeriod);
    event RewardTokenUpdated(address indexed newToken);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _rewardToken, uint256 _rewardRate, uint256 _maturityPeriod) Ownable(msg.sender) {
        require(_rewardToken != address(0), "Invalid token address");
        require(_rewardRate > 0, "Reward rate must be > 0");
        require(_maturityPeriod > 0, "Maturity period must be > 0");
        owner = msg.sender;
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        maturityPeriod = _maturityPeriod;
    }

    function stake() external payable {
        require(msg.value > 0, "Must stake more than 0");
        require(stakes[msg.sender].amount == 0, "Already staked");

        stakes[msg.sender] = Stake({amount: msg.value, startTime: block.timestamp, withdrawn: false, claimed: false});

        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function claimRewards() external hasStake {
        Stake storage s = stakes[msg.sender];
        require(!s.claimed, "Already claimed");
        require(block.timestamp >= s.startTime + maturityPeriod, "Stake not matured");

        uint256 reward = s.amount * rewardRate;
        require(rewardToken.transfer(msg.sender, reward), "Reward transfer failed");

        s.claimed = true;
        totalRewardsClaimed += reward;
        totalClaimed[msg.sender] += reward;

        emit Claimed(msg.sender, reward);
    }

    function withdraw() external hasStake {
        Stake storage s = stakes[msg.sender];
        require(!s.withdrawn, "Already withdrawn");
        require(block.timestamp >= s.startTime + maturityPeriod, "Stake not matured");

        uint256 amount = s.amount;
        s.withdrawn = true;
        totalWithdrawn[msg.sender] += amount;
        totalWithdrawals += amount;

        (bool sent,) = (msg.sender).call{value: amount}("");
        require(sent, "ETH withdrawal failed");

        emit Withdrawn(msg.sender, amount);
    }

    function emergencyWithdraw() external hasStake {
        Stake storage s = stakes[msg.sender];
        require(!s.withdrawn, "Already withdrawn");

        uint256 amount = s.amount;
        s.withdrawn = true;
        s.claimed = true;

        (bool sent,) = (msg.sender).call{value: amount}("");
        require(sent, "Emergency ETH transfer failed");

        emit EmergencyWithdraw(msg.sender, amount);
    }

    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Reward rate must be greater than 0");
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    function updateMaturityPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Maturity period must be greater than 0");
        maturityPeriod = newPeriod;
        emit MaturityPeriodUpdated(newPeriod);
    }

    function updateRewardToken(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        rewardToken = IERC20(newToken);
        emit RewardTokenUpdated(newToken);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        require(newOwner != owner, "New owner must be different");

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getStakeDetails(address user)
        external
        view
        returns (uint256 amount, uint256 startTime, bool withdrawn, bool claimed)
    {
        Stake storage s = stakes[user];
        return (s.amount, s.startTime, s.withdrawn, s.claimed);
    }

    receive() external payable {}
}
