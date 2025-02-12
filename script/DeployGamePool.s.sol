// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {GamePool} from "src/GamePool.sol";

contract DeployGamePool is Script {
    function run() external returns (GamePool) {
        vm.startBroadcast();
        GamePool pool = new GamePool(
            true,
            1 ether,
            15,
            payable(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38),
            block.timestamp,
            block.timestamp + 10 minutes
        );

        vm.stopBroadcast();
        return pool;
    }
}