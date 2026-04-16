// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./tokens/LPToken.sol";

contract AMM is ReentrancyGuard {

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    LPToken public immutable lpToken;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public constant FEE_NUMERATOR = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpMinted
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpBurned
    );

    event Swap(
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _token0, address _token1) {
        require(_token0 != address(0) && _token1 != address(0), "Zero address");
        require(_token0 != _token1, "Tokens must be different");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        lpToken = new LPToken(address(this));
    }

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant returns (uint256 lpMinted) {
        require(amount0Desired > 0 && amount1Desired > 0, "Amounts must be > 0");

        uint256 amount0;
        uint256 amount1;

        if (reserve0 == 0 && reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;

            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, "Slippage: token1 below min");
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                require(amount0Optimal >= amount0Min, "Slippage: token0 below min");
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        uint256 totalLPSupply = lpToken.totalSupply();

        if (totalLPSupply == 0) {
            lpMinted = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            lpToken.mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            lpMinted = Math.min(
                (amount0 * totalLPSupply) / reserve0,
                (amount1 * totalLPSupply) / reserve1
            );
        }

        require(lpMinted > 0, "Insufficient liquidity minted");
        lpToken.mint(msg.sender, lpMinted);

        reserve0 += amount0;
        reserve1 += amount1;

        emit LiquidityAdded(msg.sender, amount0, amount1, lpMinted);
    }

    function removeLiquidity(
        uint256 lpAmount,
        uint256 amount0Min,
        uint256 amount1Min
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(lpAmount > 0, "LP amount must be > 0");

        uint256 totalLPSupply = lpToken.totalSupply();
        require(totalLPSupply > 0, "No liquidity in pool");

        amount0 = (lpAmount * reserve0) / totalLPSupply;
        amount1 = (lpAmount * reserve1) / totalLPSupply;

        require(amount0 >= amount0Min, "Slippage: token0 below min");
        require(amount1 >= amount1Min, "Slippage: token1 below min");
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");

        lpToken.burn(msg.sender, lpAmount);

        reserve0 -= amount0;
        reserve1 -= amount1;

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, lpAmount);
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external nonReentrant returns (uint256 amountOut) {
        require(
            tokenIn == address(token0) || tokenIn == address(token1),
            "Invalid input token"
        );
        require(amountIn > 0, "Amount must be > 0");
        require(reserve0 > 0 && reserve1 > 0, "No liquidity");

        bool isToken0In = tokenIn == address(token0);

        uint256 reserveIn  = isToken0In ? reserve0 : reserve1;
        uint256 reserveOut = isToken0In ? reserve1 : reserve0;

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        require(amountOut >= amountOutMin, "Slippage exceeded");
        require(amountOut > 0, "Insufficient output amount");
        require(amountOut < reserveOut, "Not enough liquidity");

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        address tokenOut = isToken0In ? address(token1) : address(token0);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "amountIn must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "Reserves must be > 0");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);

        uint256 numerator   = reserveOut * amountInWithFee;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    function getPrice0() external view returns (uint256) {
        require(reserve0 > 0 && reserve1 > 0, "No liquidity");
        return (reserve1 * 1 ether) / reserve0;
    }

    function getPrice1() external view returns (uint256) {
        require(reserve0 > 0 && reserve1 > 0, "No liquidity");
        return (reserve0 * 1 ether) / reserve1;
    }

    function getK() external view returns (uint256) {
        return reserve0 * reserve1;
    }
}