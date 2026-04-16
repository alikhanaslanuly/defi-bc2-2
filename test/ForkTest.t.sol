// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IWETH {
    function deposit() external payable;
    function approve(address, uint256) external returns (bool);
}

contract ForkTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 constant FORK_BLOCK = 19_000_000;

    function setUp() public {
        vm.createSelectFork(
            vm.envOr("MAINNET_RPC_URL", string("https://mainnet.infura.io/v3/ce88022258c6419dab39c8483822bf97")),
            FORK_BLOCK
        );
    }

    function test_USDCTotalSupply() public view {
        uint256 supply = IERC20Minimal(USDC).totalSupply();

        assertGt(supply, 1_000_000_000e6, "Supply should be > 1B USDC");
        assertLt(supply, 100_000_000_000e6, "Supply should be < 100B USDC");

        console.log("USDC Total Supply:", supply / 1e6, "USDC");
    }

    function test_UniswapV2SwapWETHForUSDC() public {
        address trader = makeAddr("trader");
        uint256 wethAmount = 1 ether;

        vm.deal(trader, wethAmount + 0.1 ether);
        vm.prank(trader);
        IWETH(WETH).deposit{value: wethAmount}();

        assertEq(IERC20Minimal(WETH).balanceOf(trader), wethAmount);

        vm.prank(trader);
        IWETH(WETH).approve(UNI_ROUTER, wethAmount);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256 usdcBefore = IERC20Minimal(USDC).balanceOf(trader);

        vm.prank(trader);
        uint256[] memory amounts =
            IUniswapV2Router(UNI_ROUTER).swapExactTokensForTokens(wethAmount, 1, path, trader, block.timestamp + 1800);

        uint256 usdcAfter = IERC20Minimal(USDC).balanceOf(trader);

        assertGt(usdcAfter, usdcBefore, "Trader should have received USDC");
        assertGt(amounts[1], 1_000e6, "Should receive > 1000 USDC for 1 ETH");

        console.log("Received USDC:", amounts[1] / 1e6);
    }

    function test_RollForkChangesBlock() public {
        uint256 blockBefore = block.number;
        assertEq(blockBefore, FORK_BLOCK);

        vm.rollFork(FORK_BLOCK + 100);
        assertEq(block.number, FORK_BLOCK + 100);

        console.log("Block before:", blockBefore);
        console.log("Block after:", block.number);
    }

    function test_ImpersonateWhaleTransfer() public {
        address whale = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
        address recipient = makeAddr("recipient");

        uint256 whaleBalance = IERC20Minimal(USDC).balanceOf(whale);

        vm.assume(whaleBalance >= 1000e6);

        vm.prank(whale);
        IERC20Minimal(USDC).transfer(recipient, 1000e6);

        assertEq(IERC20Minimal(USDC).balanceOf(recipient), 1000e6);
    }
}
