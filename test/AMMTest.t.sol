// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "../src/tokens/TokenA.sol";
import "../src/tokens/TokenB.sol";

contract AMMTest is Test {
    AMM public amm;
    TokenA public tokenA;
    TokenB public tokenB;

    address public owner;
    address public alice;
    address public bob;

    uint256 constant INIT_A = 10_000 ether;
    uint256 constant INIT_B = 20_000 ether;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(owner);
        tokenA = new TokenA(owner);
        tokenB = new TokenB(owner);
        amm = new AMM(address(tokenA), address(tokenB));
        vm.stopPrank();

        vm.prank(owner);
        tokenA.transfer(alice, 50_000 ether);
        vm.prank(owner);
        tokenB.transfer(alice, 50_000 ether);
        vm.prank(owner);
        tokenA.transfer(bob, 10_000 ether);
        vm.prank(owner);
        tokenB.transfer(bob, 10_000 ether);
    }

    function _addInitialLiquidity() internal {
        vm.startPrank(alice);
        tokenA.approve(address(amm), INIT_A);
        tokenB.approve(address(amm), INIT_B);
        amm.addLiquidity(INIT_A, INIT_B, 0, 0);
        vm.stopPrank();
    }

    function test_AddInitialLiquidity() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), INIT_A);
        tokenB.approve(address(amm), INIT_B);
        uint256 lpMinted = amm.addLiquidity(INIT_A, INIT_B, 0, 0);
        vm.stopPrank();

        assertEq(amm.reserve0(), INIT_A);
        assertEq(amm.reserve1(), INIT_B);

        assertGt(lpMinted, 0);
        assertGt(amm.lpToken().balanceOf(alice), 0);
    }

    function test_AddSubsequentLiquidity() public {
        _addInitialLiquidity();

        uint256 lpTotalBefore = amm.lpToken().totalSupply();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 1000 ether);
        tokenB.approve(address(amm), 2000 ether);
        uint256 lpMinted = amm.addLiquidity(1000 ether, 2000 ether, 0, 0);
        vm.stopPrank();

        assertGt(lpMinted, 0);
        assertEq(amm.reserve0(), INIT_A + 1000 ether);
        assertEq(amm.reserve1(), INIT_B + 2000 ether);
        assertEq(amm.lpToken().totalSupply(), lpTotalBefore + lpMinted);
    }

    function test_RevertWhen_AddLiquidityZeroAmount() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 1000 ether);
        tokenB.approve(address(amm), 1000 ether);
        vm.expectRevert("Amounts must be > 0");
        amm.addLiquidity(0, 1000 ether, 0, 0);
        vm.stopPrank();
    }

    function test_RemoveLiquidityPartial() public {
        _addInitialLiquidity();

        uint256 aliceLPBalance = amm.lpToken().balanceOf(alice);
        uint256 halfLP = aliceLPBalance / 2;

        uint256 aliceA_before = tokenA.balanceOf(alice);
        uint256 aliceB_before = tokenB.balanceOf(alice);

        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), halfLP);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(halfLP, 0, 0);
        vm.stopPrank();

        assertGt(out0, 0);
        assertGt(out1, 0);
        assertEq(tokenA.balanceOf(alice), aliceA_before + out0);
        assertEq(tokenB.balanceOf(alice), aliceB_before + out1);
    }

    function test_RemoveLiquidityFull() public {
        _addInitialLiquidity();

        uint256 aliceLPBalance = amm.lpToken().balanceOf(alice);

        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), aliceLPBalance);
        amm.removeLiquidity(aliceLPBalance, 0, 0);
        vm.stopPrank();

        assertEq(amm.lpToken().balanceOf(alice), 0);
        assertLt(amm.reserve0(), INIT_A);
    }

    function test_RevertWhen_RemoveLiquiditySlippage() public {
        _addInitialLiquidity();
        uint256 lpBalance = amm.lpToken().balanceOf(alice);

        vm.startPrank(alice);
        amm.lpToken().approve(address(amm), lpBalance);
        vm.expectRevert("Slippage: token0 below min");
        amm.removeLiquidity(lpBalance, type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_SwapToken0ForToken1() public {
        _addInitialLiquidity();

        uint256 swapAmount = 100 ether;
        uint256 bobB_before = tokenB.balanceOf(bob);

        vm.startPrank(bob);
        tokenA.approve(address(amm), swapAmount);
        uint256 received = amm.swap(address(tokenA), swapAmount, 0);
        vm.stopPrank();

        assertGt(received, 0);
        assertEq(tokenB.balanceOf(bob), bobB_before + received);
    }

    function test_SwapToken1ForToken0() public {
        _addInitialLiquidity();

        uint256 swapAmount = 200 ether;
        uint256 bobA_before = tokenA.balanceOf(bob);

        vm.startPrank(bob);
        tokenB.approve(address(amm), swapAmount);
        uint256 received = amm.swap(address(tokenB), swapAmount, 0);
        vm.stopPrank();

        assertGt(received, 0);
        assertEq(tokenA.balanceOf(bob), bobA_before + received);
    }

    function test_SwapInvariantKNeverDecreases() public {
        _addInitialLiquidity();
        uint256 kBefore = amm.getK();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 500 ether);
        amm.swap(address(tokenA), 500 ether, 0);
        vm.stopPrank();

        uint256 kAfter = amm.getK();

        assertGe(kAfter, kBefore);
    }

    function test_RevertWhen_SwapSlippageExceeded() public {
        _addInitialLiquidity();

        uint256 amountOut = amm.getAmountOut(100 ether, amm.reserve0(), amm.reserve1());

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 ether);
        vm.expectRevert("Slippage exceeded");
        amm.swap(address(tokenA), 100 ether, amountOut + 1);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapZeroInput() public {
        _addInitialLiquidity();
        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 ether);
        vm.expectRevert("Amount must be > 0");
        amm.swap(address(tokenA), 0, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapInvalidToken() public {
        _addInitialLiquidity();
        vm.prank(bob);
        vm.expectRevert("Invalid input token");
        amm.swap(address(0xdead), 100 ether, 0);
    }

    function test_GetAmountOut_CorrectFormula() public view {
        uint256 out = amm.getAmountOut(10 ether, 100 ether, 200 ether);
        assertGt(out, 18 ether);
        assertLt(out, 19 ether);
    }

    function test_PriceAfterSwapChanges() public {
        _addInitialLiquidity();
        uint256 priceBefore = amm.getPrice0();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 1000 ether);
        amm.swap(address(tokenA), 1000 ether, 0);
        vm.stopPrank();

        uint256 priceAfter = amm.getPrice0();
        assertLt(priceAfter, priceBefore);
    }

    function testFuzz_SwapNeverDecreasesK(uint256 swapAmount) public {
        _addInitialLiquidity();

        swapAmount = bound(swapAmount, 1 ether, amm.reserve0() / 3);

        uint256 kBefore = amm.getK();

        deal(address(tokenA), bob, swapAmount);

        vm.startPrank(bob);
        tokenA.approve(address(amm), swapAmount);
        amm.swap(address(tokenA), swapAmount, 0);
        vm.stopPrank();

        uint256 kAfter = amm.getK();
        assertGe(kAfter, kBefore);
    }
}
