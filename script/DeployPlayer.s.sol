// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../test/echidna-fuzzer/Player.sol";

contract DeployPlayer is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Player player = new Player();

        vm.stopBroadcast();
    }
} 
