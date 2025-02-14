// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseGamePool} from "./BaseGamePool.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AddressValidator} from "src/utils/AddressValidator.sol";

contract GamePoolERC20 is BaseGamePool {
    using SafeERC20 for IERC20;

    IERC20 private immutable i_tokenAddress;

    error NativeTokenValueNotZero();
    error TokenTransferFailed();
    error TokenBalanceInsufficient();
    error TokenAllowanceInsufficient();

    /**
     * @dev Constructor calls BaseGamePool's constructor.
     *
     * Also validates and sets the provided ERC20 token address.
     */
    constructor(
        bool canJoinPool_,
        uint256 poolPrice_,
        uint8 commissionPercentage_,
        address payable withdrawAddress_,
        address erc20TokenAddress_,
        uint256 enrollStartTime_,
        uint256 playEndTime_
    )
        BaseGamePool(canJoinPool_, poolPrice_,  commissionPercentage_, withdrawAddress_, enrollStartTime_, playEndTime_){
            // Validate and set erc20 token address
            AddressValidator.ERC20Check(erc20TokenAddress_);
            i_tokenAddress = IERC20(erc20TokenAddress_);
        }

    function _validateAmountPaid(uint256 amount) internal override {
        if (msg.value > 0) revert NativeTokenValueNotZero();
        if (i_tokenAddress.balanceOf(msg.sender) < amount) revert TokenBalanceInsufficient();
        if (i_tokenAddress.allowance(msg.sender, address(this)) < amount) revert TokenAllowanceInsufficient();
    }

    function _sendTokenOnJoinPool(uint256 amount) internal override {
        bool success = i_tokenAddress.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TokenTransferFailed();
    }

    function _sendPrize(uint256 amount) internal override {
        bool success = i_tokenAddress.transfer(msg.sender, amount);
        if (!success) revert PrizeTransferFailed(msg.sender);
    }

    function _sendRefund(uint256 refundAmount) internal override{
        bool success = i_tokenAddress.transfer(msg.sender, refundAmount);
        if (!success) revert RefundTransferFailed(msg.sender);
    }

    function _sendOwnerCommission(uint256 commissionAmount) internal override{
        bool success = i_tokenAddress.transfer(_withdrawAddress, commissionAmount);
        if (!success) revert CommissionTransferFailed();
    }

    function _sendUnclaimedPrizes(uint256 balance) internal override {
        bool success = i_tokenAddress.transfer(_withdrawAddress, balance);
        if (!success) revert UnclaimedPrizesTransferFailed();
    }

    function getContractBalance() public view override returns (uint256) {
        return i_tokenAddress.balanceOf(address(this));
    }

    function getTokenAddress() public view returns (address) {
        return address(i_tokenAddress);
    }
}