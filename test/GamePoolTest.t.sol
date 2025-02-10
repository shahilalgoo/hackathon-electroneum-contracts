// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GamePool} from "src/GamePool.sol";
import {DeployGamePool} from "script/DeployGamePool.s.sol";
import {console2} from "forge-std/console2.sol";

contract GamePoolTest is Test {
    GamePool public pool;
    address bob = makeAddr("bob");

    uint256 public bobPrevBalance = 0;
    uint256 public ticketPrice = 1 ether;

    function setUp() public {
        DeployGamePool deployer = new DeployGamePool();
        pool = deployer.run();

        vm.deal(bob, 100 ether);
        bobPrevBalance = bob.balance;
    }

    function testBuyTicket() public {
        vm.prank(bob);
        pool.buyTicket{value: ticketPrice}();
        assertEq(bobPrevBalance - ticketPrice, bob.balance);
        assertEq(pool.getUserRecorded(bob), true);
        assertEq(pool.getUniqueParticipants(), 1);
    }

    function testInvalidPrice() public {
        vm.prank(bob);
        vm.expectRevert();
        pool.buyTicket{value: ticketPrice + 1 ether}();
    }

    function testRebuyFail() public {
        vm.startPrank(bob);
        pool.buyTicket{value: ticketPrice}();

        vm.expectRevert();
        pool.buyTicket{value: ticketPrice}();

        vm.stopPrank();
    }
}