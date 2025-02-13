// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseGamePool} from "./BaseGamePool.sol";

contract GamePoolNative is BaseGamePool {
    constructor(
        bool canJoinPool_,
        uint256 poolPrice_,
        uint8 commissionPercentage_,
        address payable withdrawAddress_,
        uint256 enrollStartTime_,
        uint256 playEndTime_
    )
        BaseGamePool(canJoinPool_, poolPrice_,  commissionPercentage_, withdrawAddress_, enrollStartTime_, playEndTime_){}

    // No implementation needed for native token
    function _sendTokenOnJoinPool(uint256 amount) internal override {}

    function _validateAmountPaid(uint256 amount) internal override {
        if (msg.value != amount) revert AmountPaidInvalid(msg.value, amount);
    }

    function _sendPrize(uint256 amount) internal override {
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert PrizeTransferFailed(msg.sender);
    }

    function _sendRefund(uint256 refundAmount) internal override{
        (bool success,) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert RefundTransferFailed(msg.sender);
    }

    function _sendOwnerCommission(uint256 commissionAmount) internal override{
        (bool success,) = _withdrawAddress.call{value: commissionAmount}("");
        if (!success) revert CommissionTransferFailed();
    }

    function _sendUnclaimedPrizes(uint256 balance) internal override {
        (bool success,) = _withdrawAddress.call{value: balance}("");
        if (!success) revert UnclaimedPrizesTransferFailed();
    }

    function getContractBalance() public view override returns (uint256) {
        return address(this).balance;
    }
}