// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {GamePoolERC20} from "src/GamePoolERC20.sol";
import {DeployGamePoolERC20} from "script/DeployGamePoolERC20.s.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20} from "src/utils/MockERC20.sol";

contract GamePoolERC20Test is Test {
    GamePoolERC20 public pool;
    MockERC20 public mockERC20;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address charlie = makeAddr("charlie");
    address david = makeAddr("david");
    address eve = makeAddr("eve");
    address frank = makeAddr("frank");
    address grace = makeAddr("grace");
    address henry = makeAddr("henry");
    address isabella = makeAddr("isabella");
    address john = makeAddr("john");

    uint256 public bobPrevBalance = 0;
    uint256 public poolPrice = 1 ether;

    function setUp() public {
        DeployGamePoolERC20 deployer = new DeployGamePoolERC20();
        pool = deployer.run();
        mockERC20 = deployer.mockERC20();

        vm.startPrank(msg.sender);
        vm.deal(bob, 100 ether);
        mockERC20.transfer(bob, 1 ether);
        mockERC20.transfer(alice, 1 ether);
        mockERC20.transfer(charlie, 1 ether);
        mockERC20.transfer(david, 1 ether);
        mockERC20.transfer(eve, 1 ether);
        mockERC20.transfer(frank, 1 ether);
        mockERC20.transfer(grace, 1 ether);
        mockERC20.transfer(henry, 1 ether);
        mockERC20.transfer(isabella, 1 ether);
        mockERC20.transfer(john, 1 ether);
        vm.stopPrank();
        bobPrevBalance = mockERC20.balanceOf(bob);
    }

    modifier approvals() {
        vm.prank(bob);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(alice);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(charlie);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(david);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(eve);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(frank);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(grace);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(henry);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(isabella);
        mockERC20.approve(address(pool), 1 ether);
        vm.prank(john);
        mockERC20.approve(address(pool), 1 ether);
        _;
    }

    function testJoinPool() public approvals {
        vm.startPrank(bob);
        pool.joinPool();
        assertEq(bobPrevBalance - poolPrice, mockERC20.balanceOf(bob));
        assertEq(pool.getUserRecorded(bob), true);
        assertEq(pool.getUniqueParticipants(), 1);
        uint256 currentCommission = (pool.getCommissionPercentage() *
            mockERC20.balanceOf(address(pool))) / 100;
        assertEq(pool.getCurrentCommission(), currentCommission);

        vm.expectRevert();
        pool.joinPool{value: poolPrice}();
        vm.stopPrank();
    }

    function testCannotBuyWithNativeToken() public {
        vm.deal(bob, 1 ether);
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: 1 ether}();
    }

    function testTokenBalanceInsufficient() public {
        vm.expectRevert();
        vm.prank(alice);
        pool.joinPool();
    }

    function testTokenAllowanceInsufficient() public {
        vm.startPrank(bob);
        mockERC20.approve(address(pool), poolPrice / 2);
        vm.expectRevert();
        pool.joinPool();
        vm.stopPrank();
    }

    function testAllowInvalidAmount() public {
        vm.startPrank(bob);
        mockERC20.approve(address(pool), poolPrice / 2);
        vm.expectRevert();
        pool.joinPool();
        assertEq(bobPrevBalance, mockERC20.balanceOf(bob));
        assertEq(pool.getUserRecorded(bob), false);
        assertEq(pool.getUniqueParticipants(), 0);
        vm.stopPrank();
    }

    function testSendingETH() public {
        vm.startPrank(bob);
        vm.expectRevert();
        pool.joinPool{value: 1 ether}();
        vm.stopPrank();
    }

    function testERC20Refund() public approvals {
        vm.prank(bob);
        pool.joinPool();

        assertEq(pool.getContractBalance(), mockERC20.balanceOf(address(pool)));
        vm.warp(pool.getPlayEndTime() + 10);
        vm.prank(msg.sender);
        pool.enableRefund();
        assertEq(pool.getCanRefund(), true);
        assertEq(pool.getCanJoinPool(), false);

        // bob claims refund
        vm.prank(bob);
        pool.claimRefund();

        assertEq(mockERC20.balanceOf(bob), bobPrevBalance);
        assertEq(pool.getUserRefundClaim(bob), true);
        assertEq(pool.getRefundClaimCount(), 1);
        assertEq(pool.getContractBalance(), 0);

        // test bob cannot claim again
        vm.expectRevert();
        vm.prank(bob);
        pool.claimRefund();
    }

    function testWithdrawUnclaimedPrizesToken() public {
        vm.prank(msg.sender);
        mockERC20.transfer(address(pool), 55 ether);

        vm.warp(pool.getClaimExpiryTime() + 1);
        vm.roll(block.number + 15);

        uint256 contractPrevBalance = mockERC20.balanceOf(address(pool));
        uint256 withdrawAddressPrevBalance = mockERC20.balanceOf(
            pool.getWithdrawAddress()
        );

        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();

        assertEq(mockERC20.balanceOf(address(pool)), 0);
        assertEq(
            mockERC20.balanceOf(pool.getWithdrawAddress()),
            withdrawAddressPrevBalance + contractPrevBalance
        );

        // attempt to withdraw again
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();
    }

    function testClaimCommissionERC20() public {
        // go past playtime
        vm.warp(pool.getPlayEndTime() + 10);
        vm.roll(block.number + 15);

        vm.prank(msg.sender);
        mockERC20.transfer(address(pool), 100 ether);

        // set fake merkle root
        vm.prank(msg.sender);
        pool.setPrizeMerkleRoot(
            0xa608b0934eef3f6889620db202010e1f63bc79069f02151dfb115392042aae5b
        );

        uint256 contractPrevBalance = mockERC20.balanceOf(address(pool));
        uint256 withdrawAddressPrevBalance = mockERC20.balanceOf(
            pool.getWithdrawAddress()
        );

        uint256 commissionAmount = pool.getCurrentCommission();

        vm.prank(msg.sender);
        pool.claimOwnerCommission();

        assertEq(pool.getCommissionClaimed(), true);
        assertEq(
            mockERC20.balanceOf(pool.getWithdrawAddress()),
            withdrawAddressPrevBalance + commissionAmount
        );
        assertEq(
            mockERC20.balanceOf(address(pool)),
            contractPrevBalance - commissionAmount
        );

        // check cannot claim twice
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.claimOwnerCommission();
    }

    function testERC20GamePoolLifecycle() public approvals {
        // make all of them join the pool
        vm.prank(bob);
        pool.joinPool();
        vm.prank(alice);
        pool.joinPool();
        vm.prank(charlie);
        pool.joinPool();
        vm.prank(david);
        pool.joinPool();
        vm.prank(eve);
        pool.joinPool();
        vm.prank(frank);
        pool.joinPool();
        vm.prank(grace);
        pool.joinPool();
        vm.prank(henry);
        pool.joinPool();
        vm.prank(isabella);
        pool.joinPool();
        vm.prank(john);
        pool.joinPool();

        bobPrevBalance = mockERC20.balanceOf(bob);
        uint256 alicePrevBalance = mockERC20.balanceOf(alice);
        uint256 charliePrevBalance = mockERC20.balanceOf(charlie);
        uint256 commPrevBalance = mockERC20.balanceOf(msg.sender);

        assertEq(pool.getUniqueParticipants(), 10);
        assertEq(pool.getContractBalance(), 10 * poolPrice);

        //go after playtime
        vm.warp(pool.getPlayEndTime() + 10);
        bytes32 root = 0xbbba43a4d5e2204d76c0605d3501a54a6b3cd68924cc45275fb6fa0a7e58f4b8;
        vm.prank(msg.sender);
        pool.setPrizeMerkleRoot(root);

        // Claim structure
        // Bob : 1 ether
        // Alice : 2 ether
        // Charlie : 4 ether
        // Me : 1.5 ether representing 15% for communities
        // Commission : 1.5 ether representing 15% for owner

        // BOB
        bytes32[] memory proofBob = new bytes32[](2);
        proofBob[
            0
        ] = 0xebc0fb39cae4d144f70999865aa49dd4a395e0735ea7e718bcb9b36c21bd40c2;
        proofBob[
            1
        ] = 0x1df7d5b4678fceba4e25d8bd22f9b390e17dbb651eb49668bec54ee09d0ce2e4;

        vm.prank(bob);
        pool.claimPrize(proofBob, 1 ether);
        assertEq(mockERC20.balanceOf(bob), bobPrevBalance + 1 ether);
        assertEq(pool.getPrizeClaimCount(), 1);
        assertEq(pool.getUserPrizeClaim(bob), true);
        assertEq(mockERC20.balanceOf(address(pool)), 9 ether);

        // ALICE
        bytes32[] memory proofAlice = new bytes32[](2);
        proofAlice[
            0
        ] = 0xc6e0378439d1724db2b66a0d3d9abe00f5a0a4c024f42d9418ecf98e0fd3afd7;
        proofAlice[
            1
        ] = 0x0e08ee3d7727ff444ec924de6e45e218e347ac603c0239e8dc03ce1e52e591af;

        vm.expectRevert();
        vm.prank(alice);
        pool.claimPrize(proofAlice, 10 ether);

        vm.prank(alice);
        pool.claimPrize(proofAlice, 2 ether);
        assertEq(mockERC20.balanceOf(alice), alicePrevBalance + 2 ether);
        assertEq(pool.getPrizeClaimCount(), 2);
        assertEq(pool.getUserPrizeClaim(alice), true);
        assertEq(mockERC20.balanceOf(address(pool)), 7 ether);

        // CHARLIE
        bytes32[] memory proofCharlie = new bytes32[](2);
        proofCharlie[
            0
        ] = 0x91f0946464aa7ec225a6fe8d6c3e196078687e2b51bcf5666e1289cbd40f949c;
        proofCharlie[
            1
        ] = 0x0e08ee3d7727ff444ec924de6e45e218e347ac603c0239e8dc03ce1e52e591af;

        vm.prank(charlie);
        pool.claimPrize(proofCharlie, 4 ether);
        assertEq(mockERC20.balanceOf(charlie), charliePrevBalance + 4 ether);
        assertEq(pool.getPrizeClaimCount(), 3);
        assertEq(pool.getUserPrizeClaim(charlie), true);
        assertEq(mockERC20.balanceOf(address(pool)), 3 ether);

        // COMMUNITIES - msg.sender representing communities
        bytes32[] memory proofComm = new bytes32[](2);
        proofComm[
            0
        ] = 0xecbc9750276e1ad49333464b124e860719bba0133709bc7860e6b4262f17360a;
        proofComm[
            1
        ] = 0x1df7d5b4678fceba4e25d8bd22f9b390e17dbb651eb49668bec54ee09d0ce2e4;

        vm.prank(msg.sender);
        pool.claimPrize(proofComm, 1.5 ether);
        assertEq(mockERC20.balanceOf(msg.sender), commPrevBalance + 1.5 ether);
        assertEq(pool.getPrizeClaimCount(), 4);
        assertEq(pool.getUserPrizeClaim(msg.sender), true);
        assertEq(mockERC20.balanceOf(address(pool)), 1.5 ether);

        // OWNER
        uint256 withdrawerPrevBalance = mockERC20.balanceOf(
            pool.getWithdrawAddress()
        );
        console2.log(pool.getCurrentCommission());
        vm.prank(msg.sender);
        pool.claimOwnerCommission();
        assertEq(
            mockERC20.balanceOf(pool.getWithdrawAddress()),
            withdrawerPrevBalance + 1.5 ether
        );

        assertEq(pool.getCommissionClaimed(), true);
        assertEq(pool.getContractBalance(), 0);

        // let's pretend there was 1 ether left in the contract
        vm.prank(msg.sender);
        mockERC20.transfer(address(pool), 1 ether);
        withdrawerPrevBalance = mockERC20.balanceOf(pool.getWithdrawAddress());
        vm.warp(pool.getClaimExpiryTime() + 10);
        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();
        assertEq(pool.getContractBalance(), 0);
        assertEq(
            mockERC20.balanceOf(pool.getWithdrawAddress()),
            withdrawerPrevBalance + 1 ether
        );
    }
}
