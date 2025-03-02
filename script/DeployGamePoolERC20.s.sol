// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {GamePoolERC20} from "src/GamePoolERC20.sol";
import {MockERC20} from "../src/utils/MockERC20.sol";

contract DeployGamePoolERC20 is Script {
    MockERC20 public mockERC20;

    function run() external returns (GamePoolERC20) {
        vm.startBroadcast();
        mockERC20 = new MockERC20(100000 ether);

        GamePoolERC20 pool = new GamePoolERC20(
            true,
            1 ether,
            15,
            payable(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38),
            address(mockERC20),
            block.timestamp,
            block.timestamp + 10 minutes
        );

        vm.stopBroadcast();
        return pool;
    }
}
