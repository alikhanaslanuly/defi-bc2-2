// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/tokens/TokenA.sol";
import "../src/tokens/TokenB.sol";
import "../src/AMM.sol";
import "../src/LendingPool.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        TokenA tokenA = new TokenA(deployer);
        TokenB tokenB = new TokenB(deployer);

        AMM amm = new AMM(address(tokenA), address(tokenB));

        LendingPool lendingPool = new LendingPool(address(tokenA), 2000 ether);

        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 20_000 ether);
        amm.addLiquidity(10_000 ether, 20_000 ether, 0, 0);

        tokenA.approve(address(lendingPool), 50_000 ether);
        lendingPool.deposit(50_000 ether);

        vm.stopBroadcast();

        console.log("=== DEPLOYED CONTRACTS ===");
        console.log("TokenA:      ", address(tokenA));
        console.log("TokenB:      ", address(tokenB));
        console.log("AMM:         ", address(amm));
        console.log("LP Token:    ", address(amm.lpToken()));
        console.log("LendingPool: ", address(lendingPool));
    }
}
