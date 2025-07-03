// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Contract for staking Ether and claiming rewards in ERC20 tokens
// Users can stake Ether, claim rewards after a maturity period, and withdraw their stake
contract Staking is Ownable {
    // State variables to hold contract parameters
    // rewardToken: The ERC20 token used for rewards
    ERC20 public rewardToken;
    uint256 public rewardRate;
    uint256 public maturityPeriod;
    uint256 public totalStaked;
    uint256 public totalWithdrawals;
    uint256 public totalRewardsClaimed;

    // Struct to hold stake details for each user
    // amount: The amount of Ether staked
    struct Stake {
        uint256 amount;
        uint256 startTime;
        bool withdrawn;
        bool claimed;
    }

    // Mapping from user address to their stake details
    // Allows us to track each user's stake, start time, and status of withdrawal/claim
    mapping(address => Stake) public stakes;

    // Events to log important actions
    // Staked: Emitted when a user stakes Ether
    event Staked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 reward);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event MaturityPeriodUpdated(uint256 newPeriod);
    event RewardTokenUpdated(address indexed newToken);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    // hasStake: Ensures that the user has a stake before allowing certain actions
    modifier hasStake() {
        require(stakes[msg.sender].amount > 0, "No stake found");
        _;
    }
    // Constructor to initialize the contract with the owner, reward token, reward rate, and maturity period
    // initialOwner: The address of the contract owner

    constructor(address initialOwner, address _rewardToken, uint256 _rewardRate, uint256 _maturityPeriod)
        Ownable(initialOwner)
    {
        require(_rewardToken != address(0), "Invalid token address");
        require(_rewardRate > 0, "Reward rate must be > 0");
        require(_maturityPeriod > 0, "Maturity period must be > 0");
        rewardToken = ERC20(_rewardToken);
        rewardRate = _rewardRate;
        maturityPeriod = _maturityPeriod;
    }

    // Function to stake Ether
    // Users can call this function to stake Ether and start earning rewards
    function stake() external payable {
        require(msg.value > 0, "Must stake more than 0");
        require(stakes[msg.sender].amount == 0, "Already staked");

        stakes[msg.sender] = Stake({amount: msg.value, startTime: block.timestamp, withdrawn: false, claimed: false});

        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    // Function to claim rewards after the maturity period
    // Users can call this function to claim their rewards in ERC20 tokens after the maturity period
    function claimRewards() external hasStake {
        Stake storage s = stakes[msg.sender];
        require(!s.claimed, "Already claimed");
        require(block.timestamp >= s.startTime + maturityPeriod, "Stake not matured");

        uint256 reward = s.amount * rewardRate;
        require(rewardToken.transfer(msg.sender, reward), "Reward transfer failed");

        s.claimed = true;
        totalRewardsClaimed += reward;

        emit Claimed(msg.sender, reward);
    }

    // Function to withdraw the staked Ether after the maturity period
    // Users can call this function to withdraw their staked Ether after the maturity period
    function withdraw() external hasStake {
        Stake storage s = stakes[msg.sender];
        require(!s.withdrawn, "Already withdrawn");
        require(block.timestamp >= s.startTime + maturityPeriod, "Stake not matured");

        uint256 amount = s.amount;
        s.withdrawn = true;
        totalWithdrawals += amount;

        (bool sent,) = payable(msg.sender).call{value: amount}("");
        require(sent, "ETH withdrawal failed");
    }

    // Emergency withdrawal function
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

    // Owner functions to update parameters
    // These functions allow the contract owner to update the reward rate, maturity period, and reward
    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Reward rate must be greater than 0");
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    // Function to update the maturity period
    // Allows the owner to change the maturity period for staking
    function updateMaturityPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Maturity period must be greater than 0");
        maturityPeriod = newPeriod;
        emit MaturityPeriodUpdated(newPeriod);
    }

    // Function to update the reward token
    // Allows the owner to change the ERC20 token used for rewards
    function updateRewardToken(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        rewardToken = ERC20(newToken);
        emit RewardTokenUpdated(newToken);
    }

    // Function to transfer ownership of the contract
    // Allows the current owner to transfer ownership to a new address
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        require(newOwner != owner(), "New owner must be different");

        _transferOwnership(newOwner);
    }

    // View functions to get contract state
    // These functions allow users to query the contract state without modifying it
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    // function to get Stake details for a user
    // Returns the amount staked, start time, withdrawal status, and claim status for a
    function getStakeDetails(address user)
        external
        view
        returns (uint256 amount, uint256 startTime, bool withdrawn, bool claimed)
    {
        Stake storage s = stakes[user];
        return (s.amount, s.startTime, s.withdrawn, s.claimed);
    }

    // Fallback function to receive Ether
    // This function allows the contract to receive Ether directly
    receive() external payable {}
}
