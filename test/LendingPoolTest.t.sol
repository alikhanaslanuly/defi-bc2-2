// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/tokens/TokenA.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    TokenA public usdc;

    address public owner;
    address public alice;
    address public bob;
    address public liquidator;

    uint256 constant ETH_PRICE = 2000 ether;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        liquidator = makeAddr("liquidator");

        vm.startPrank(owner);
        usdc = new TokenA(owner);
        pool = new LendingPool(address(usdc), ETH_PRICE);
        vm.stopPrank();

        vm.prank(owner);
        usdc.transfer(alice, 50_000 ether);

        vm.prank(owner);
        usdc.transfer(liquidator, 10_000 ether);

        vm.deal(bob, 10 ether);
        vm.deal(alice, 5 ether);
    }

    function _aliceDepositsToPool(uint256 amount) internal {
        vm.startPrank(alice);
        usdc.approve(address(pool), amount);
        pool.deposit(amount);
        vm.stopPrank();
    }

    function test_DepositTokens() public {
        _aliceDepositsToPool(10_000 ether);

        assertEq(pool.totalSupplied(), 10_000 ether);
        (,, uint256 supplied) = _getUserAccountFields(alice);
        assertEq(supplied, 10_000 ether);
    }

    function test_WithdrawTokens() public {
        _aliceDepositsToPool(10_000 ether);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        pool.withdraw(5_000 ether);

        assertEq(usdc.balanceOf(alice), balanceBefore + 5_000 ether);
        assertEq(pool.totalSupplied(), 5_000 ether);
    }

    function test_RevertWhen_WithdrawMoreThanDeposited() public {
        _aliceDepositsToPool(1_000 ether);

        vm.prank(alice);
        vm.expectRevert("Insufficient deposit");
        pool.withdraw(2_000 ether);
    }

    function test_DepositCollateral() public {
        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();

        (uint256 collateral,,) = _getUserAccountFields(bob);
        assertEq(collateral, 2 ether);
    }

    function test_RevertWhen_DepositZeroCollateral() public {
        vm.prank(bob);
        vm.expectRevert("Must send ETH");
        pool.depositCollateral{value: 0}();
    }

    function test_BorrowWithinLTV() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        pool.borrow(1_000 ether);

        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 1_000 ether);
        assertEq(pool.totalBorrowed(), 1_000 ether);
    }

    function test_RevertWhen_BorrowExceedsLTV() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 1 ether}();

        vm.prank(bob);
        vm.expectRevert("Exceeds LTV limit");
        pool.borrow(2_000 ether);
    }

    function test_RevertWhen_BorrowWithZeroCollateral() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        vm.expectRevert("Exceeds LTV limit");
        pool.borrow(100 ether);
    }

    function test_RepayPartial() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();
        vm.prank(bob);
        pool.borrow(1_000 ether);

        vm.startPrank(bob);
        usdc.approve(address(pool), 500 ether);
        pool.repay(500 ether);
        vm.stopPrank();

        (, uint256 borrowed,) = _getUserAccountFields(bob);
        assertEq(borrowed, 500 ether);
    }

    function test_RepayFull() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();
        vm.prank(bob);
        pool.borrow(1_000 ether);

        vm.startPrank(bob);
        usdc.approve(address(pool), 1_000 ether);
        pool.repay(1_000 ether);
        vm.stopPrank();

        (, uint256 borrowed,) = _getUserAccountFields(bob);
        assertEq(borrowed, 0);
        assertEq(pool.getHealthFactor(bob), type(uint256).max);
    }

    function test_HealthFactorAboveOne_WhenSafe() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();
        vm.prank(bob);
        pool.borrow(1_000 ether);

        uint256 hf = pool.getHealthFactor(bob);
        assertGt(hf, 1 ether);
    }

    function test_LiquidationAfterPriceDrop() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 1 ether}();
        vm.prank(bob);
        pool.borrow(1_400 ether);

        vm.prank(owner);
        pool.setEthPrice(1_500 ether);

        assertLt(pool.getHealthFactor(bob), 1 ether);

        uint256 liquidatorEthBefore = liquidator.balance;

        vm.startPrank(liquidator);
        usdc.approve(address(pool), 700 ether);
        pool.liquidate(bob, 700 ether);
        vm.stopPrank();

        assertGt(liquidator.balance, liquidatorEthBefore);
    }

    function test_RevertWhen_LiquidateHealthyPosition() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 2 ether}();
        vm.prank(bob);
        pool.borrow(1_000 ether);

        vm.startPrank(liquidator);
        usdc.approve(address(pool), 500 ether);
        vm.expectRevert("Position is healthy");
        pool.liquidate(bob, 500 ether);
        vm.stopPrank();
    }

    function test_InterestAccruesOverTime() public {
        _aliceDepositsToPool(10_000 ether);

        vm.prank(bob);
        pool.depositCollateral{value: 3 ether}();
        vm.prank(bob);
        pool.borrow(1_000 ether);

        uint256 debtAtStart = pool.getCurrentDebt(bob);

        vm.warp(block.timestamp + 30 days);

        uint256 debtAfter = pool.getCurrentDebt(bob);

        assertGt(debtAfter, debtAtStart);
    }

    function test_UtilizationRateUpdatesOnBorrow() public {
        _aliceDepositsToPool(10_000 ether);
        assertEq(pool.getUtilizationRate(), 0);

        vm.prank(bob);
        pool.depositCollateral{value: 3 ether}();
        vm.prank(bob);
        pool.borrow(4_000 ether);

        assertEq(pool.getUtilizationRate(), 0.4 ether);
    }

    function _getUserAccountFields(address user)
        internal
        view
        returns (uint256 collateral, uint256 borrowed, uint256 supplied)
    {
        (collateral, borrowed, supplied,) = pool.accounts(user);
    }
}
