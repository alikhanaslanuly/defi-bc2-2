// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenA is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor(address initialOwner) ERC20("Token A", "TKNA") Ownable(initialOwner) {
        _mint(initialOwner, 100_000 ether);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
}