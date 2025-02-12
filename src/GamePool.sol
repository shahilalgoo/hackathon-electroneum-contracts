// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VerifyProof} from "src/utils/VerifyProof.sol";

contract GamePool is Ownable, ReentrancyGuard {
    /**
     * ERRORS
     */
    // Constructor Errors
    error WithdrawAddressCannotBeZeroAddress();
    error CommissionPercentageTooHigh();
    error TicketPriceCannotBeZero();

    // Modifier Errors
    error EnrollmentPhaseInactive();
    error PlaytimeOver();
    error PlaytimeNotOver();
    error ClaimPhaseOver();

    // Buy Ticket Errors
    error TicketSaleAlreadySetTo(bool value);
    error TicketSaleInactive();
    error UserAlreadyHasTicket();
    error AmountPaidInvalid(uint256 paid, uint256 price);
    error PrizeStructureInPlace();

    // Claim Errors
    error PrizeStructureNotSet();
    error UserAlreadyClaimed(address user);
    error PrizeTransferFailed(address recipient);

    // Merkle Root Errors
    error MerkleRootCannotBeZero();

    // Refund Errors
    error RefundInactive();
    error RefundAlreadyClaimed(address user);
    error RefundTransferFailed(address recipient);
    error RefundInPlace();
    error RefundCountNotZero(uint32 count);
    error RefundAlreadyInactive();

    // Commission Errors
    error NoCommissionToClaim();
    error CommissionAlreadyClaimed();
    error CommissionTransferFailed();
    
    // Unclaimed Withdrawal Errors
    error UnclaimedPrizesTransferFailed();
    error ClaimExpiryTimeNotReached();
    error NoUnclaimedPrizes();


    /**
     * CONSTANTS/IMMUTABLES
     */
    uint8 private constant MAX_OWNER_COMMISSION_PERCENTAGE = 15;
    uint256 private constant CLAIM_EXPIRY_TIME = 30 days;
    uint256 private immutable i_enrollStartTime;
    uint256 private immutable i_playEndTime;
    uint256 private immutable i_claimExpiryTime;
    uint256 private immutable i_ticketPrice;
    uint8 private immutable i_commissionPercentage;

    /**
     * STATE VARIABLES
     */
    bool private _canBuyTicket;
    bool private _refundActivated;
    bool private _commissionClaimed;
    uint32 private _uniqueParticipants;
    bytes32 private _prizeMerkleRoot;
    uint32 private _prizeClaimCount;
    uint32 private _refundClaimCount;
    uint256 private _balanceAfterPlaytime;
    address payable private _withdrawAddress;

    mapping(address => bool) private _participantRecorded;
    mapping(address => bool) private _prizeClaims;
    mapping(address => bool) private _refundClaims;

    /**
     * EVENTS
     */
    event WithdrawAddressUpdated(address indexed newWithdrawAddress);
    event TicketSaleEnabled(bool value);
    event TicketBought(address indexed participant);
    event MerkleRootSet(bytes32 merkleRoot);
    event PrizeClaimed(address indexed participant, uint256 amount);
    event RefundClaimed(address indexed participant, uint256 amount);
    event OwnerCommissionClaimed(address indexed to, uint256 amount);
    event UnclaimedPrizesWithdrawn(uint256 amount);
    event RefundEnabled();
    event RefundDisabled();


    constructor(
        bool canBuyTicket_, 
        uint256 ticketPrice_,
        uint8 commissionPercentage_,
        address payable withdrawAddress_,
        uint256 enrollStartTime_, 
        uint256 playEndTime_) 
        Ownable() {
        // Commission cannot be higher than 15%
        if (commissionPercentage_ > MAX_OWNER_COMMISSION_PERCENTAGE) revert CommissionPercentageTooHigh();

        // Ticket price cannot be zero
        if (ticketPrice_ == 0) revert TicketPriceCannotBeZero(); 

        // Withdraw address cannot be zero address
        if (withdrawAddress_ == address(0)) revert WithdrawAddressCannotBeZeroAddress();

        _canBuyTicket = canBuyTicket_;
        i_ticketPrice = ticketPrice_;
        _withdrawAddress = withdrawAddress_;
        i_commissionPercentage = commissionPercentage_;

        // Enroll start time cannot be less than now
        i_enrollStartTime = enrollStartTime_ < block.timestamp ? block.timestamp : enrollStartTime_;

        // Play end time cannot be less than 10 minutes from now
        i_playEndTime = playEndTime_ < block.timestamp + 10 minutes ? block.timestamp + 10 minutes : playEndTime_;

        i_claimExpiryTime = playEndTime_ + CLAIM_EXPIRY_TIME;
    }

    modifier enrollPhase() {
        // Check if within enrollment/playtime
        if (block.timestamp < i_enrollStartTime || block.timestamp > i_playEndTime) revert EnrollmentPhaseInactive();
        _;
    }

    modifier afterPlaytimePhase() {
        if (block.timestamp <= i_playEndTime) revert PlaytimeNotOver();
        _;
    }

    modifier claimPhase() {
        if (block.timestamp > i_claimExpiryTime) revert ClaimPhaseOver();
        _;
    }

    function updateWithdrawAddress(address payable newWithdrawAddress) external onlyOwner {
        if (newWithdrawAddress == address(0)) revert WithdrawAddressCannotBeZeroAddress();
        _withdrawAddress = newWithdrawAddress;

        emit WithdrawAddressUpdated(newWithdrawAddress);
    }

    function enableBuyTicket(bool value) external onlyOwner enrollPhase {
        // Check refund state
        if (value == true && _refundActivated) revert RefundInPlace();
        
        // Check merkle root is not set
        if (value == true && _prizeMerkleRoot != bytes32(0)) revert PrizeStructureInPlace();

        if (_canBuyTicket == value) revert TicketSaleAlreadySetTo(value);

        _canBuyTicket = value;

        emit TicketSaleEnabled(value);
    }

    function enableRefund() external virtual onlyOwner claimPhase {
        if (_refundActivated) revert RefundInPlace();

        // Check merkle root is not set
        if (_prizeMerkleRoot != bytes32(0)) revert PrizeStructureInPlace();

        _canBuyTicket = false;
        _refundActivated = true;

        emit RefundEnabled();
    }

    function disableRefund(bool canBuyTicket) external virtual onlyOwner {
        if (!_refundActivated) revert RefundAlreadyInactive();

        if (_refundClaimCount > 0) revert RefundCountNotZero(_refundClaimCount);

        _canBuyTicket = canBuyTicket;
        _refundActivated = false;

        emit RefundDisabled();
    }


    function setPrizeMerkleRoot(bytes32 merkleRoot) public virtual onlyOwner claimPhase afterPlaytimePhase {
        // Check refund is not activated
        if (_refundActivated) revert RefundInPlace();

        // merkle root cannot be zero
        if (merkleRoot == bytes32(0)) revert MerkleRootCannotBeZero();

        // Disable ticket buying bool
        _canBuyTicket = false;

        // Record balance after playtime, so we can calculate commission
        _balanceAfterPlaytime = address(this).balance;

        _prizeMerkleRoot = merkleRoot;

        emit MerkleRootSet(merkleRoot);
    }

    function buyTicket() external payable enrollPhase nonReentrant {
        // Check active ticket buying
        if (!_canBuyTicket) revert TicketSaleInactive();

        // Check if user already has ticket
        if (_participantRecorded[msg.sender]) revert UserAlreadyHasTicket();

        // Check if amount paid/allowed is correct
        if (msg.value != i_ticketPrice) revert AmountPaidInvalid(msg.value, i_ticketPrice);

        // Count unique participant
        unchecked {
            _uniqueParticipants++;
        }

        // Record participant
        _participantRecorded[msg.sender] = true;

        emit TicketBought(msg.sender);
    }

    function claimPrize(bytes32[] calldata proof, uint256 amount) external claimPhase afterPlaytimePhase nonReentrant {
        // Check if merkle root is set
        if (_prizeMerkleRoot == bytes32(0)) revert PrizeStructureNotSet();

        // Check if user has already claimed
        if (_prizeClaims[msg.sender]) revert UserAlreadyClaimed(msg.sender);

        // Verify proof
        VerifyProof.verify(proof, amount, _prizeMerkleRoot);

        // Update claims
        unchecked {
            _prizeClaimCount++;
        }

        _prizeClaims[msg.sender] = true;

        emit PrizeClaimed(msg.sender, amount);

        // Send prize
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert PrizeTransferFailed(msg.sender);
    }

    function claimRefund() external virtual claimPhase nonReentrant {
        // Ensure refund process is activated
        if (!_refundActivated) revert RefundInactive();

        // Check if user has already claimed
        if (_refundClaims[msg.sender]) revert RefundAlreadyClaimed(msg.sender);

        // Mark refund as claimed
        _refundClaims[msg.sender] = true;
        unchecked {
            _refundClaimCount++;
        }

        emit RefundClaimed(msg.sender, i_ticketPrice);

        // Send refund
        (bool success,) = payable(msg.sender).call{value: i_ticketPrice}("");
        if (!success) revert RefundTransferFailed(msg.sender);
    }

    function claimOwnerCommission() external virtual onlyOwner afterPlaytimePhase {
        // Make owner claim only after the prize structure is in place
        if (_prizeMerkleRoot == bytes32(0)) revert PrizeStructureNotSet();

        // Check if already claimed
        if (_commissionClaimed) revert CommissionAlreadyClaimed();

        // Check commission amount
        uint256 commissionAmount = getCurrentCommission();
        if (commissionAmount == 0) revert NoCommissionToClaim();

        _commissionClaimed = true;

        emit OwnerCommissionClaimed(_withdrawAddress, commissionAmount);

       (bool success,) = _withdrawAddress.call{value: commissionAmount}("");
        if (!success) revert CommissionTransferFailed();
    }


    function withdrawUnclaimedPrizes() external onlyOwner {
         // Check expiry time
        if (block.timestamp < i_claimExpiryTime) {
            revert ClaimExpiryTimeNotReached();
        }

        // Determine the balance of the contract
        uint256 balance = address(this).balance;

        // Ensure there is a balance to withdraw
        if (balance == 0) revert NoUnclaimedPrizes();

        emit UnclaimedPrizesWithdrawn(balance);

        // Withdraw unclaimed prizes
        (bool success,) = _withdrawAddress.call{value: balance}("");
        if (!success) revert UnclaimedPrizesTransferFailed();
    }



    /**
     * GETTERS
     */

    function getCanBuyTicket() public view returns (bool) {
        return _canBuyTicket;
    }

    function getCanRefund() public view returns (bool) {
        return _refundActivated;
    }

    function getWithdrawAddress() public view returns (address) {
        return _withdrawAddress;
    }

    function getEnrollStartTime() public view returns (uint256) {
        return i_enrollStartTime;
    }

    function getPlayEndTime() public view returns (uint256) {
        return i_playEndTime;
    }

    function getClaimExpiryTime() public view returns (uint256) {
        return i_claimExpiryTime;
    }

    function getTicketPrice() public view returns (uint256) {
        return i_ticketPrice;
    }

    function getUserRecorded(address user) public view returns (bool) {
        return _participantRecorded[user];
    }

    function getUniqueParticipants() public view returns (uint32) {
        return _uniqueParticipants;
    }

    function getPrizeMerkleRoot() public view returns (bytes32) {
        return _prizeMerkleRoot;
    }

    function getPrizeClaimCount() public view returns (uint32) {
        return _prizeClaimCount;
    }

    function getUserPrizeClaim(address user) public view returns (bool) {
        return _prizeClaims[user];
    }

    function getRefundClaimCount() public view returns (uint32) {
        return _refundClaimCount;
    }

    function getUserRefundClaim(address user) public view returns (bool) {
        return _refundClaims[user];
    }

    function getCurrentCommission() public view returns (uint256) {
        if (_prizeMerkleRoot == bytes32(0)) {
            return i_commissionPercentage * address(this).balance / 100;
        } else {
            return i_commissionPercentage * _balanceAfterPlaytime / 100;
        }
    }

    function getCommissionClaimed() public view returns (bool) {
        return _commissionClaimed;
    }
}