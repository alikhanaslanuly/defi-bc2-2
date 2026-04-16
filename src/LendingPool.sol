// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LendingPool is ReentrancyGuard {

    IERC20 public immutable borrowToken;

    address public owner;

    uint256 public constant LTV = 75e16; 
    uint256 public constant LIQUIDATION_THRESHOLD = 80e16;
    uint256 public constant LIQUIDATION_BONUS = 5e16;  
    uint256 public constant CLOSE_FACTOR = 50e16; 
    uint256 public constant BASE_RATE = 2e16;  
    uint256 public constant SLOPE = 20e16;
    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_IN_YEAR = 365 days;

    uint256 public totalSupplied;  
    uint256 public totalBorrowed;  
    uint256 public lastUpdateTimestamp;
    uint256 public accruedInterestIndex; 

    uint256 public ethPriceUSD;


    struct UserAccount {
        uint256 collateralETH;
        uint256 borrowed;     
        uint256 supplied;      
        uint256 borrowIndex;   
    }

    mapping(address => UserAccount) public accounts;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event DepositCollateral(address indexed user, uint256 ethAmount);
    event WithdrawCollateral(address indexed user, uint256 ethAmount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event PriceUpdated(uint256 newPrice);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _borrowToken, uint256 _initialEthPrice) {
        require(_borrowToken != address(0), "Zero address");
        require(_initialEthPrice > 0, "Invalid price");

        borrowToken = IERC20(_borrowToken);
        owner = msg.sender;
        ethPriceUSD = _initialEthPrice;
        lastUpdateTimestamp = block.timestamp;
        accruedInterestIndex = WAD; 
    }

    function setEthPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid price");
        _accrueInterest();
        ethPriceUSD = newPrice;
        emit PriceUpdated(newPrice);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest();

        borrowToken.transferFrom(msg.sender, address(this), amount);
        accounts[msg.sender].supplied += amount;
        totalSupplied += amount;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _accrueInterest();
        UserAccount storage user = accounts[msg.sender];
        require(user.supplied >= amount, "Insufficient deposit");

        uint256 availableLiquidity = totalSupplied - totalBorrowed;
        require(availableLiquidity >= amount, "Insufficient pool liquidity");

        user.supplied -= amount;
        totalSupplied -= amount;

        borrowToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function depositCollateral() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        _accrueInterest();

        accounts[msg.sender].collateralETH += msg.value;
        emit DepositCollateral(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        _accrueInterest();
        UserAccount storage user = accounts[msg.sender];
        require(user.collateralETH >= amount, "Not enough collateral");

        user.collateralETH -= amount;

        if (user.borrowed > 0) {
            require(getHealthFactor(msg.sender) >= WAD, "Would be liquidatable");
        }

        payable(msg.sender).transfer(amount);
        emit WithdrawCollateral(msg.sender, amount);
    }

    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest();

        uint256 availableLiquidity = totalSupplied - totalBorrowed;
        require(availableLiquidity >= amount, "Insufficient pool liquidity");

        UserAccount storage user = accounts[msg.sender];

        user.borrowIndex = accruedInterestIndex;

        user.borrowed += amount;
        totalBorrowed += amount;

        uint256 collateralValue = getCollateralValueUSD(msg.sender);
        uint256 maxBorrowUSD = (collateralValue * LTV) / WAD;

        require(user.borrowed <= maxBorrowUSD, "Exceeds LTV limit");

        borrowToken.transfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        _accrueInterest();

        UserAccount storage user = accounts[msg.sender];
        uint256 currentDebt = getCurrentDebt(msg.sender);
        require(currentDebt > 0, "No debt to repay");

        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        borrowToken.transferFrom(msg.sender, address(this), repayAmount);

        if (repayAmount >= user.borrowed) {
            user.borrowed = 0;
        } else {
            user.borrowed -= repayAmount;
        }

        totalBorrowed = totalBorrowed >= repayAmount ? totalBorrowed - repayAmount : 0;

        emit Repay(msg.sender, repayAmount);
    }

    function liquidate(address borrower, uint256 debtToRepay) external nonReentrant {
        _accrueInterest();

        require(borrower != msg.sender, "Cannot liquidate yourself");

        require(getHealthFactor(borrower) < WAD, "Position is healthy");

        UserAccount storage user = accounts[borrower];
        uint256 currentDebt = getCurrentDebt(borrower);
        require(currentDebt > 0, "No debt");

        uint256 maxRepay = (currentDebt * CLOSE_FACTOR) / WAD;
        require(debtToRepay > 0 && debtToRepay <= maxRepay, "Invalid repay amount");

        uint256 collateralToSeize = (debtToRepay * WAD * (WAD + LIQUIDATION_BONUS))
            / (ethPriceUSD * WAD);

        require(collateralToSeize <= user.collateralETH, "Not enough collateral");
        require(collateralToSeize > 0, "Zero collateral to seize");

        borrowToken.transferFrom(msg.sender, address(this), debtToRepay);

        user.borrowed = user.borrowed >= debtToRepay ? user.borrowed - debtToRepay : 0;
        totalBorrowed = totalBorrowed >= debtToRepay ? totalBorrowed - debtToRepay : 0;
        user.collateralETH -= collateralToSeize;

        payable(msg.sender).transfer(collateralToSeize);

        emit Liquidated(borrower, msg.sender, debtToRepay, collateralToSeize);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        UserAccount memory u = accounts[user];
        if (u.borrowed == 0) return type(uint256).max;

        uint256 collateralValue = getCollateralValueUSD(user);
        uint256 currentDebt = getCurrentDebt(user);

        return (collateralValue * LIQUIDATION_THRESHOLD) / currentDebt;
    }

    function getCollateralValueUSD(address user) public view returns (uint256) {
        return (accounts[user].collateralETH * ethPriceUSD) / WAD;
    }

    function getMaxBorrow(address user) public view returns (uint256) {
        uint256 collateralValue = getCollateralValueUSD(user);
        uint256 maxBorrow = (collateralValue * LTV) / WAD;
        uint256 currentDebt = getCurrentDebt(user);
        return maxBorrow > currentDebt ? maxBorrow - currentDebt : 0;
    }

    function _calculateCurrentIndex() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) return accruedInterestIndex;

        uint256 borrowRate = getBorrowRate();
        uint256 interestFactor = (borrowRate * timeElapsed) / SECONDS_IN_YEAR;
        return accruedInterestIndex + (accruedInterestIndex * interestFactor) / WAD;
}

    function getCurrentDebt(address user) public view returns (uint256) {
        UserAccount memory u = accounts[user];
        if (u.borrowed == 0) return 0;
        
        uint256 currentIndex = _calculateCurrentIndex(); // Берем актуальный индекс
        return (u.borrowed * currentIndex) / u.borrowIndex;
}

    function getBorrowRate() public view returns (uint256) {
        if (totalSupplied == 0) return BASE_RATE;

        uint256 utilization = (totalBorrowed * WAD) / totalSupplied;
        return BASE_RATE + (utilization * SLOPE) / WAD;
    }

    function getUtilizationRate() public view returns (uint256) {
        if (totalSupplied == 0) return 0;
        return (totalBorrowed * WAD) / totalSupplied;
    }

    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) return;

        uint256 borrowRate = getBorrowRate();

        uint256 interestFactor = (borrowRate * timeElapsed) / SECONDS_IN_YEAR;
        accruedInterestIndex += (accruedInterestIndex * interestFactor) / WAD;

        lastUpdateTimestamp = block.timestamp;
    }
}