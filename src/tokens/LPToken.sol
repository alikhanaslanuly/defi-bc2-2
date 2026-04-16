// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPToken is ERC20 {
    address public immutable amm;

    modifier onlyAMM() {
        require(msg.sender == amm, "Only AMM can call this");
        _;
    }

    constructor(address _amm) ERC20("AMM LP Token", "LP") {
        require(_amm != address(0), "Zero address");
        amm = _amm;
    }

    function mint(address to, uint256 amount) external onlyAMM {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyAMM {
        _burn(from, amount);
    }
}
