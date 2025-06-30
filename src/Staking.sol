// SPDX-License-Identifier: MIT
pragma solidity ^0.5.11;

// users stake eth get Rewarded in erc20 after stake matures

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

contract EthStaking {
    // State variables
    IERC20 public rewardToken;
    address public owner;
    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public maturityPeriod;
    mapping(address => uint256) public stakes;
    mapping(address => uint256) public rewards;

    struct StakeInfo {
        uint256 amount;
        uint256 stakeTime;
        bool rewarded;
        uint256 timestamp;
        bool claimed;
    }
    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Rewarded(address indexed user, uint256 reward);

    // Constructor
    constructor() {
        owner = msg.sender;
    }

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    // Functions
    function stake() external payable {
        require(msg.value > 0, "Must stake a positive amount");
        stakes[msg.sender] += msg.value;
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function unstake(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Insufficient stake");
        stakes[msg.sender] -= amount;
        totalStaked -= amount;
        address(msg.sender).transfer(amount);
        emit Unstaked(msg.sender, amount);
    }

    function reward(address user, uint256 rewardAmount) external onlyOwner {
        rewards[user] += rewardAmount;
        emit Rewarded(user, rewardAmount);
    }
}