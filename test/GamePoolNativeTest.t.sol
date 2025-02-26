// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GamePoolNative} from "src/GamePoolNative.sol";
import {DeployGamePoolNative} from "script/DeployGamePoolNative.s.sol";
import {console2} from "forge-std/console2.sol";

contract GamePoolTest is Test {
    GamePoolNative public pool;
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address charlie = makeAddr("charlie");
    // bob: 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e
    // alice: 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6
    // charlie: 0xea475d60c118d7058beF4bDd9c32bA51139a74e0

    uint256 public bobPrevBalance = 0;
    uint256 public poolPrice = 1 ether;

    function setUp() public {
        DeployGamePoolNative deployer = new DeployGamePoolNative();
        pool = deployer.run();

        vm.deal(bob, 100 ether);
        bobPrevBalance = bob.balance;

        vm.deal(alice, 1 ether);
        vm.deal(charlie, 1 ether);
    }

     // test send funds to contract
    function testSendFundsDirectlyToContract() public {
        vm.prank(bob);
        (bool success,) = address(pool).call{value: 10 ether}("");
        assertEq(success, false);
        assertEq(address(pool).balance, 0);
    }

    function testCannotBuyWithInactivePoolIntake() public {
        vm.prank(msg.sender);
        pool.enableJoinPool(false);
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
    }

    function testCannotJoinPoolWithInsufficientFunds() public {
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice/2}();
    }

     function testCannotJoinPoolTwice() public {
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
    }

    function testCannotJoinPoolBeforeEnrollmentPhase() public {
        vm.warp(0);
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
    }

    function testCannotJoinPoolAfterPlaytime() public {
        vm.warp(pool.getPlayEndTime() + 10);
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
    }

    function testDisableJoinPool() public {
        vm.prank(msg.sender);
        pool.enableJoinPool(false);
        vm.expectRevert();
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
    }

    function testCannotSetJoinPoolToSameValue() public {
        vm.prank(msg.sender);
        pool.enableJoinPool(false);
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.enableJoinPool(false);
    }

    function testCannotEnableJoinPoolAfterRefundActivated() public {
        vm.prank(msg.sender);
        pool.enableRefund();
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.enableJoinPool(true);
    }

    function testEnableJoinPoolAfterDisabling() public {
        vm.prank(msg.sender);
        pool.enableJoinPool(false);
        vm.prank(msg.sender);
        pool.enableJoinPool(true);
        assertEq(pool.getCanJoinPool(), true);
    }

    function testJoinPool() public {
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
        assertEq(bobPrevBalance - poolPrice, bob.balance);
        assertEq(pool.getUserRecorded(bob), true);
        assertEq(pool.getUniqueParticipants(), 1);
    }

    function testInvalidPrice() public {
        vm.prank(bob);
        vm.expectRevert();
        pool.joinPool{value: poolPrice + 1 ether}();
    }

    function testRebuyFail() public {
        vm.startPrank(bob);
        pool.joinPool{value: poolPrice}();

        vm.expectRevert();
        pool.joinPool{value: poolPrice}();

        vm.stopPrank();
    }

    function testBuyFailAfterEnrollmentPhase() public {
        vm.warp(pool.getPlayEndTime() + 10);
        vm.expectRevert();
        vm.startPrank(bob);
        pool.joinPool{value: poolPrice}();
        vm.stopPrank();
    }

    function testSetMerkle() public merkleSetup {
        vm.prank(msg.sender);
        pool.setPrizeMerkleRoot(0xa608b0934eef3f6889620db202010e1f63bc79069f02151dfb115392042aae5b);
        assertEq(
            pool.getPrizeMerkleRoot(), 0xa608b0934eef3f6889620db202010e1f63bc79069f02151dfb115392042aae5b
        );
    }

    function testClaimPrize() public {
        
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();
        vm.prank(alice);
        pool.joinPool{value: poolPrice}();
        vm.prank(charlie);
        pool.joinPool{value: poolPrice}();

        assertEq(pool.getUniqueParticipants(), 3);
        assertEq(pool.getPoolPrice(), poolPrice);
        assertEq(pool.getCommissionPercentage(), 15);
        assertEq(pool.getPrizePool(), poolPrice * 3 * 85 / 100);

        uint256 alicePrevBalance = alice.balance;
        uint256 charliePrevBalance = charlie.balance;

        //go after playtime
        vm.warp(pool.getPlayEndTime() + 10);
        bytes32 root = 0x28c5c02cb9e3f98af47ead6cc0a3efeea9aebbbf2118d9a0fad2fc8b2520bc67;
        vm.prank(msg.sender);
        pool.setPrizeMerkleRoot(root);

        // BOB
        bytes32[] memory proofBob = new bytes32[](1);
        proofBob[0] = 0xdd1c535cc8d1ab705c6c9d65b873474a7225d917648f9edc09bda4f851b4318d;

        vm.prank(bob);
        pool.claimPrize(proofBob, 1 ether);
        assertEq(bob.balance, bobPrevBalance);
        assertEq(pool.getPrizeClaimCount(), 1);
        assertEq(pool.getUserPrizeClaim(bob), true);
        assertEq(address(pool).balance, 2 ether);

        // ALICE
        bytes32[] memory proofAlice = new bytes32[](2);
        proofAlice[0] = 0xe41e3096cba7e4fa7e65e44b27890c4d99e274f7c58788c4131e5bddecacb99e;
        proofAlice[1] = 0xecbc9750276e1ad49333464b124e860719bba0133709bc7860e6b4262f17360a;

        vm.expectRevert();
        vm.prank(alice);
        pool.claimPrize(proofAlice, 10 ether);

        vm.prank(alice);
        pool.claimPrize(proofAlice, 1 ether);
        assertEq(alice.balance, alicePrevBalance + 1 ether);
        assertEq(pool.getPrizeClaimCount(), 2);
        assertEq(pool.getUserPrizeClaim(alice), true);
        assertEq(address(pool).balance, 1 ether);

        // CHARLIE
        bytes32[] memory proofCharlie = new bytes32[](2);
        proofCharlie[0] = 0x42cc8a55e963e0472bfe88474c638d374e1a860c2580fcf2d5ef698fbfd830c3;
        proofCharlie[1] = 0xecbc9750276e1ad49333464b124e860719bba0133709bc7860e6b4262f17360a;

        vm.prank(charlie);
        pool.claimPrize(proofCharlie, 1 ether);
        assertEq(charlie.balance, charliePrevBalance + 1 ether);
        assertEq(pool.getPrizeClaimCount(), 3);
        assertEq(pool.getUserPrizeClaim(charlie), true);
        assertEq(address(pool).balance, 0 ether);

    }

    modifier merkleSetup() {
        vm.warp(pool.getPlayEndTime() + 10);
        _;
    }

    function testClaimCommission() public merkleSetup {
        uint256 funds = 100 ether;
        uint256 withdrawerPrevBalance = pool.getWithdrawAddress().balance;
        vm.prank(msg.sender);
        vm.deal(address(pool), funds);
        pool.setPrizeMerkleRoot(0xa608b0934eef3f6889620db202010e1f63bc79069f02151dfb115392042aae5b);
        uint256 contractPrevBalance = address(pool).balance;
        uint256 commissionAmount = pool.getCurrentCommission();
        vm.prank(msg.sender);
        pool.claimOwnerCommission();
        assertEq(pool.getCommissionClaimed(), true);
        assertEq(pool.getWithdrawAddress().balance, withdrawerPrevBalance + commissionAmount);
        assertEq(address(pool).balance, contractPrevBalance - commissionAmount);

        // check cannot claim twice
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.claimOwnerCommission();
    }

    function testWithdrawUnclaimedPrizes() public {
        // let's pretend there was 1 ether left in the contract
        uint256 withdrawerPrevBalance = pool.getWithdrawAddress().balance;
        vm.deal(address(pool), 1 ether);
        vm.warp(pool.getClaimExpiryTime() + 10);
        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();
        assertEq(address(pool).balance, 0);
        assertEq(pool.getWithdrawAddress().balance, withdrawerPrevBalance + 1 ether);
    }

    function testDenyWithdrawUnclaimedPrizesIfNotOwner() public {
        vm.expectRevert();
        vm.prank(bob);
        pool.withdrawUnclaimedPrizes();
    }

    function testDenyWithdrawBeforeClaimExpiry() public {
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();
    }

    function testNoUnclaimedPrizes() public {
        vm.warp(pool.getClaimExpiryTime() + 31 days);
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.withdrawUnclaimedPrizes();
    }

    function testRefundInactive() public {
        vm.expectRevert();
        vm.startPrank(bob);
        pool.claimRefund();
        vm.stopPrank();
    }

    function testRefund() public {
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();

        vm.warp(pool.getPlayEndTime() + 10);
        vm.prank(msg.sender);
        pool.enableRefund();
        assertEq(pool.getCanRefund(), true);
        assertEq(pool.getCanJoinPool(), false);

        // bob claims refund
        vm.prank(bob);
        pool.claimRefund();

        assertEq(bob.balance, bobPrevBalance);
        assertEq(pool.getUserRefundClaim(bob), true);
        assertEq(pool.getRefundClaimCount(), 1);
        assertEq(address(pool).balance, 0);
    }

    function testRefundAlreadyActive() public {
        vm.prank(msg.sender);
        pool.enableRefund();
        assertEq(pool.getCanRefund(), true);
        assertEq(pool.getCanJoinPool(), false);
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.enableRefund();
    }

    function testCannotRefundIfNotInPool() public {
        vm.prank(msg.sender);
        pool.enableRefund();

        vm.expectRevert();
        vm.prank(alice);
        pool.claimRefund();
    }

    function testCannotActivateRefundIfRootExists() public {
        vm.warp(pool.getPlayEndTime() + 10);
        vm.prank(msg.sender);
        pool.setPrizeMerkleRoot(0xa608b0934eef3f6889620db202010e1f63bc79069f02151dfb115392042aae5b);
        vm.expectRevert();
        vm.prank(msg.sender);
        pool.enableRefund();
    }

    function testCannotDisableRefundTwice() public {
        vm.startPrank(msg.sender);
        pool.enableRefund();
        pool.disableRefund(false);
        vm.expectRevert();
        pool.disableRefund(false);
        vm.stopPrank();
    }

    function testCannotDisableRefundIfClaimsExist() public {
        vm.prank(bob);
        pool.joinPool{value: poolPrice}();

        vm.prank(msg.sender);
        pool.enableRefund();

        vm.prank(bob);
        pool.claimRefund();

        vm.expectRevert();
        vm.prank(msg.sender);
        pool.disableRefund(false);
    }

    function testRefundInvalid() public {
        vm.prank(msg.sender);
        pool.enableRefund();
        vm.expectRevert();
        vm.prank(bob);
        pool.claimRefund();
        assertEq(pool.getUserRefundClaim(bob), false);
    }

    function testRefundClaimExpired() public {
        vm.prank(msg.sender);
        pool.enableRefund();
        vm.warp(pool.getClaimExpiryTime() + 31 days);
        vm.expectRevert();
        vm.prank(bob);
        pool.claimRefund();
    }
}