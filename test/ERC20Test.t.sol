// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/TokenA.sol";

contract ERC20Test is Test {
    TokenA public token;

    address public owner;
    address public alice;
    address public bob;
    address public carol;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        vm.prank(owner);
        token = new TokenA(owner);

        vm.prank(owner);
        token.transfer(alice, 1000 ether);
        vm.prank(owner);
        token.transfer(bob, 500 ether);
    }

    function test_Name() public view {
        assertEq(token.name(), "Token A");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "TKNA");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), 100_000 ether);
    }

    function test_MintByOwner() public {
        uint256 supplyBefore = token.totalSupply();
        vm.prank(owner);
        token.mint(carol, 500 ether);

        assertEq(token.totalSupply(), supplyBefore + 500 ether);
        assertEq(token.balanceOf(carol), 500 ether);
    }

    function test_RevertWhen_MintByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000 ether);
    }

    function test_RevertWhen_MintExceedsMaxSupply() public {
        vm.prank(owner);
        vm.expectRevert("Exceeds max supply");
        token.mint(carol, 999_000 ether + 1);
    }

    function test_Transfer() public {
        vm.prank(alice);
        token.transfer(carol, 100 ether);

        assertEq(token.balanceOf(alice), 900 ether);
        assertEq(token.balanceOf(carol), 100 ether);
    }

    function test_TransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(alice, carol, 100 ether);

        vm.prank(alice);
        token.transfer(carol, 100 ether);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(carol, 9999 ether);
    }

    function test_TransferToSelf() public {
        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(alice), balanceBefore);
    }

    function test_Approve() public {
        vm.prank(alice);
        token.approve(bob, 200 ether);

        assertEq(token.allowance(alice, bob), 200 ether);
    }

    function test_TransferFrom() public {
        vm.prank(alice);
        token.approve(bob, 200 ether);

        vm.prank(bob);
        token.transferFrom(alice, carol, 150 ether);

        assertEq(token.balanceOf(alice), 850 ether);
        assertEq(token.balanceOf(carol), 150 ether);
        assertEq(token.allowance(alice, bob), 50 ether);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        vm.prank(alice);
        token.approve(bob, 50 ether);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, carol, 100 ether);
    }

    function test_RevertWhen_TransferFromWithoutApprove() public {
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, carol, 1 ether);
    }

    function test_TransferZeroAmount() public {
        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(carol, 0);
        assertEq(token.balanceOf(alice), balanceBefore);
    }

    function test_ApproveOverwritesPrevious() public {
        vm.prank(alice);
        token.approve(bob, 100 ether);
        vm.prank(alice);
        token.approve(bob, 200 ether);
        assertEq(token.allowance(alice, bob), 200 ether);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(alice));

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 carolBefore = token.balanceOf(carol);

        vm.prank(alice);
        token.transfer(carol, amount);

        assertEq(token.balanceOf(alice), aliceBefore - amount);
        assertEq(token.balanceOf(carol), carolBefore + amount);
    }

    function invariant_TotalSupplyUnchangedByTransfer() public view {
        assertEq(token.totalSupply(), 100_000 ether);
    }

    function invariant_NoBalanceExceedsTotalSupply() public view {
        assertLe(token.balanceOf(alice), token.totalSupply());
        assertLe(token.balanceOf(bob), token.totalSupply());
        assertLe(token.balanceOf(carol), token.totalSupply());
        assertLe(token.balanceOf(owner), token.totalSupply());
    }
}
