// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Simple mock ERC20 using OpenZeppelin's implementation
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract StakingTest is Test {
    event Staked(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event MaturityPeriodUpdated(uint256 newPeriod);
    event RewardTokenUpdated(address indexed newToken);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    Staking staking;
    MockERC20 mockToken;

    function setUp() public {
        mockToken = new MockERC20();
        // Pass 4 arguments: initialOwner, rewardToken, rewardRate, maturityPeriod
        staking = new Staking(address(this), address(mockToken), 5, 100);
        mockToken.transfer(address(staking), 1000 ether);
        vm.deal(address(this), 1 ether); // Fund the test contract with some ether
        mockToken.approve(address(staking), 1000 ether); // Approve the staking
    }

    function testInitialValues() public view {
        assertEq(address(staking.rewardToken()), address(mockToken));
        assertEq(staking.rewardRate(), 5);
        assertEq(staking.maturityPeriod(), 100);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.totalWithdrawals(), 0);
        assertEq(staking.totalRewardsClaimed(), 0);
    }

    function testStakeStructInitialization() public {
        // Simulate a user staking Ether
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.getStakeDetails(address(this));

        assertEq(amount, 1 ether);
        assertEq(withdrawn, false);
        assertEq(claimed, false);
        assertGe(startTime, block.number); // startBlock is current or past block
    }

    function testStakesMappingStoresCorrectly() public {
        vm.deal(address(this), 2 ether);
        staking.stake{value: 2 ether}();

        // Access the public mapping directly
        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.stakes(address(this));

        assertEq(amount, 2 ether);
        assertEq(withdrawn, false);
        assertEq(claimed, false);
        assertGe(startTime, block.number); // For block.number or timestamp depending on your version
    }

    function testConstructorInitializesCorrectly() public {
        address initialOwner = address(0xBEEF);
        vm.prank(initialOwner);
        Staking s = new Staking(initialOwner, address(mockToken), 10, 200);

        assertEq(address(s.rewardToken()), address(mockToken));
        assertEq(s.rewardRate(), 10);
        assertEq(s.maturityPeriod(), 200);
        assertEq(s.owner(), initialOwner);
    }

    function testConstructorRevertsOnZeroToken() public {
        address initialOwner = address(this);
        vm.expectRevert("Invalid token address");
        new Staking(initialOwner, address(0), 10, 100);
    }

    function testConstructorRevertsOnZeroRate() public {
        address initialOwner = address(this);
        vm.expectRevert("Reward rate must be > 0");
        new Staking(initialOwner, address(mockToken), 0, 100);
    }

    function testConstructorRevertsOnZeroMaturity() public {
        address initialOwner = address(this);
        vm.expectRevert("Maturity period must be > 0");
        new Staking(initialOwner, address(mockToken), 5, 0);
    }

    function testStake() public {
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.getStakeDetails(address(this));

        assertEq(amount, 1 ether);
        assertGe(startTime, block.number); // startBlock is current or past block
        assertEq(withdrawn, false);
        assertEq(claimed, false);
    }

    function testStakeEtherSuccessfully() public {
        vm.deal(address(this), 2 ether); // Give test contract 2 ether

        vm.expectEmit(true, true, false, true);
        emit Staked(address(this), 2 ether);

        staking.stake{value: 2 ether}();

        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.getStakeDetails(address(this));

        assertEq(amount, 2 ether);
        assertEq(withdrawn, false);
        assertEq(claimed, false);
        assertGe(startTime, block.timestamp);
        assertEq(staking.totalStaked(), 2 ether);
    }

    function testStakeRevertsOnZeroAmount() public {
        vm.expectRevert("Must stake more than 0");
        staking.stake{value: 0}();
    }

    function testStakeRevertsOnAlreadyStaked() public {
        vm.deal(address(this), 2 ether);
        staking.stake{value: 1 ether}();
        vm.expectRevert("Already staked");
        staking.stake{value: 1 ether}();
    }

    function testClaimRewards() public {
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        // Fast-forward time by maturityPeriod seconds
        vm.warp(block.timestamp + staking.maturityPeriod());

        uint256 rewardAmount = 1 ether * staking.rewardRate();

        // Ensure staking contract has enough tokens before claiming
        // (if not already done in setUp)
        mockToken.transfer(address(staking), rewardAmount);

        uint256 balanceBefore = mockToken.balanceOf(address(this));
        staking.claimRewards();
        uint256 balanceAfter = mockToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, rewardAmount);
    }

    function testClaimRewardsAfterMaturity() public {
        address user = address(0xBEEF);
        vm.deal(user, 1 ether);

        // Stake 1 ether
        vm.prank(user);
        staking.stake{value: 1 ether}();

        // Fast forward time past maturity
        vm.warp(block.timestamp + 1 days + 1);

        // Give staking contract enough reward tokens
        mockToken.transfer(address(staking), 5 ether); // rewardRate is 5

        // Check balance before
        uint256 beforeBalance = mockToken.balanceOf(user);

        // Claim rewards
        vm.prank(user);
        staking.claimRewards();

        // Expected reward: 1 ether * 5
        uint256 expectedReward = 1 ether * 5;

        // Check balance after
        uint256 afterBalance = mockToken.balanceOf(user);
        assertEq(afterBalance, beforeBalance + expectedReward);

        // Check total rewards claimed
        assertEq(staking.totalRewardsClaimed(), expectedReward);

        // Revert on double claim
        vm.expectRevert("Already claimed");
        vm.prank(user);
        staking.claimRewards();
    }

    function testWithdraw() public {
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        vm.warp(block.timestamp + staking.maturityPeriod());

        // If required
        staking.claimRewards();

        uint256 balanceBefore = address(this).balance;
        staking.withdraw();
        uint256 balanceAfter = address(this).balance;

        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    receive() external payable {}

    function testWithdrawAfterMaturity() public {
        uint256 stakeAmount = 1 ether;
        vm.deal(address(this), stakeAmount);

        staking.stake{value: stakeAmount}();

        vm.warp(block.timestamp + staking.maturityPeriod());

        uint256 balanceBefore = address(this).balance;
        staking.withdraw();
        uint256 balanceAfter = address(this).balance;

        emit log_named_uint("Balance before", balanceBefore);
        emit log_named_uint("Balance after", balanceAfter);
        emit log_named_uint("Balance delta", balanceAfter - balanceBefore);

        assertEq(balanceAfter - balanceBefore, stakeAmount);

        (,,, bool withdrawn) = staking.stakes(address(this));
        emit log_named_string("Was withdrawn true?", withdrawn ? "true" : "false");
    }

    function testCannotWithdrawBeforeMaturity() public {
        uint256 stakeAmount = 1 ether;
        vm.deal(address(this), stakeAmount);

        staking.stake{value: stakeAmount}();

        vm.expectRevert("Stake not matured");
        staking.withdraw();
    }

    function testCannotWithdrawTwice() public {
        uint256 stakeAmount = 1 ether;
        vm.deal(address(this), stakeAmount);

        staking.stake{value: stakeAmount}();
        vm.warp(block.timestamp + staking.maturityPeriod());

        staking.withdraw();

        vm.expectRevert("Already withdrawn");
        staking.withdraw();
    }

    function testEmergencyWithdraw() public {
        uint256 stakeAmount = 1 ether;
        vm.deal(address(this), stakeAmount);

        staking.stake{value: stakeAmount}();

        // Emergency withdraw
        staking.emergencyWithdraw();
    }

    function testCannotEmergencyWithdrawTwice() public {
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        staking.emergencyWithdraw();

        vm.expectRevert("Already withdrawn");
        staking.emergencyWithdraw();
    }

    function testUpdateRewardRate() public {
        uint256 newRate = 10;
        staking.updateRewardRate(newRate);
        assertEq(staking.rewardRate(), newRate);
    }

    function testUpdateRewardRateFailsForZero() public {
        // vm.prank(notOwner);
        vm.expectRevert("Reward rate must be greater than 0");
        staking.updateRewardRate(0);
    }

    function testUpdateRewardRateFailsForNonOwner() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        staking.updateRewardRate(10);
    }

    function testUpdateMaturityPeriod() public {
        uint256 newPeriod = 7 days;

        vm.expectEmit(true, false, false, true);
        emit MaturityPeriodUpdated(newPeriod);

        staking.updateMaturityPeriod(newPeriod);

        assertEq(staking.maturityPeriod(), newPeriod);
    }

    function testUpdateMaturityPeriodFailsWithZero() public {
        vm.prank(staking.owner());
        vm.expectRevert("Maturity period must be greater than 0");
        staking.updateMaturityPeriod(0);
    }

    function testUpdateMaturityPeriodFailsForNonOwner() public {
        address notOwner = address(0xBEEF);
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        staking.updateMaturityPeriod(5 days);
    }

    function testUpdateMaturityPeriodRevertsOnZero() public {
        address owner = staking.owner();
        vm.prank(owner);
        vm.expectRevert("Maturity period must be greater than 0");
        staking.updateMaturityPeriod(0);
    }

    function testUpdateRewardToken() public {
        address newRewardToken = address(new MockERC20());
        vm.prank(staking.owner());
        vm.expectEmit(true, true, true, true);
        emit RewardTokenUpdated(newRewardToken);
        staking.updateRewardToken(newRewardToken);
    }

    function testUpdateRewardTokenFailsForZeroAddress() public {
        address owner = staking.owner();
        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        staking.updateRewardToken(address(0));
    }

    function testUpdateRewardTokenFailsForNonOwner() public {
        address notOwner = address(0xBEEF);
        MockERC20 newToken = new MockERC20();

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        staking.updateRewardToken(address(newToken));
    }

    function testTransferOwnership() public {
        address newOwner = address(0xBEEF);

        // Ensure msg.sender is the current owner
        vm.prank(staking.owner()); // Use the current owner from the staking contract
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(staking.owner(), newOwner);

        staking.transferOwnership(newOwner);

        assertEq(staking.owner(), newOwner);
    }

    function testTransferOwnershipFailsForNonOwner() public {
        address notOwner = address(0xBAD);
        address newOwner = address(0xBEEF);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        staking.transferOwnership(newOwner);
    }

    function testTransferOwnershipFailsForZeroAddress() public {
        address owner = staking.owner();
        vm.prank(owner);
        vm.expectRevert("New owner cannot be zero address");
        staking.transferOwnership(address(0));
    }

    function testGetTotalStaked() public {
        // Stake 1 ether
        vm.deal(address(this), 1 ether);
        staking.stake{value: 1 ether}();

        // Check if getTotalStaked returns 1 ether
        uint256 total = staking.getTotalStaked();
        assertEq(total, 1 ether);
    }

    function testGetTotalStakedMultipleUsers() public {
        address user1 = address(0xA1);
        address user2 = address(0xB2);

        vm.deal(user1, 2 ether);
        vm.deal(user2, 3 ether);

        vm.prank(user1);
        staking.stake{value: 2 ether}();

        vm.prank(user2);
        staking.stake{value: 3 ether}();

        assertEq(staking.getTotalStaked(), 5 ether);
    }

    function testGetStakeDetails() public {
        uint256 stakeAmount = 1 ether;

        vm.deal(address(this), stakeAmount);
        staking.stake{value: stakeAmount}();

        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.getStakeDetails(address(this));

        assertEq(amount, stakeAmount);
        assertGt(startTime, 0); // Ensure timestamp was set
        assertFalse(withdrawn);
        assertFalse(claimed);
    }

    function testGetStakeDetailsWhenEmpty() public view {
        address user = address(0xBEEF);
        (uint256 amount, uint256 startTime, bool withdrawn, bool claimed) = staking.getStakeDetails(user);

        assertEq(amount, 0);
        assertEq(startTime, 0);
        assertFalse(withdrawn);
        assertFalse(claimed);
    }
}
