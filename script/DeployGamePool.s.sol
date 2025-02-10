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
            block.timestamp,
            block.timestamp + 10 minutes
        );

        vm.stopBroadcast();
        return pool;
    }
}