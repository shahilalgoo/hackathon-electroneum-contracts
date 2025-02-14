// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VerifyProof} from "src/utils/VerifyProof.sol";

abstract contract BaseGamePool is Ownable, ReentrancyGuard {
    /**
     * ERRORS
     */
    // Constructor Errors
    error WithdrawAddressCannotBeZeroAddress();
    error CommissionPercentageTooHigh();
    error PoolPriceCannotBeZero();

    // Modifier Errors
    error EnrollmentPhaseInactive();
    error PlaytimeOver();
    error PlaytimeNotOver();
    error ClaimPhaseOver();

    // Join Pool Errors
    error PoolIntakeAlreadySetTo(bool value);
    error PoolIntakeInactive();
    error UserAlreadyInPool();
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
    error UserNotInPool(address user);

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
    uint8 private constant MAX_OWNER_COMMISSION_PERCENTAGE = 30;
    uint256 private constant CLAIM_EXPIRY_TIME = 30 days;
    uint256 private immutable i_enrollStartTime;
    uint256 private immutable i_playEndTime;
    uint256 private immutable i_claimExpiryTime;
    uint256 private immutable i_poolPrice;
    uint8 private immutable i_commissionPercentage;

    /**
     * STATE VARIABLES
     */
    bool private _canJoinPool;
    bool private _refundActivated;
    bool private _commissionClaimed;
    uint32 private _uniqueParticipants;
    bytes32 private _prizeMerkleRoot;
    uint32 private _prizeClaimCount;
    uint32 private _refundClaimCount;
    uint256 private _balanceAfterPlaytime;
    address payable internal _withdrawAddress;

    mapping(address => bool) private _participantRecorded;
    mapping(address => bool) private _prizeClaims;
    mapping(address => bool) private _refundClaims;

    /**
     * EVENTS
     */
    event WithdrawAddressUpdated(address indexed newWithdrawAddress);
    event PoolIntakeEnabled(bool value);
    event PoolJoined(address indexed participant);
    event MerkleRootSet(bytes32 merkleRoot);
    event PrizeClaimed(address indexed participant, uint256 amount);
    event RefundClaimed(address indexed participant, uint256 amount);
    event OwnerCommissionClaimed(address indexed to, uint256 amount);
    event UnclaimedPrizesWithdrawn(uint256 amount);
    event RefundEnabled();
    event RefundDisabled();

    /**
     * @dev Initializes contract state based on provided configuration for commission, withdraw address, timings,
     * - `withdrawAddress_` must be a non-zero address.
     * - `enrollStartTime_` defaults to current block time if set in the past.
     * - `playEndTime_` defaults to current block time + 10 minutes if set within 10 minutes of the current time.
     */
    constructor(
        bool canJoinPool_, 
        uint256 poolPrice_,
        uint8 commissionPercentage_,
        address payable withdrawAddress_,
        uint256 enrollStartTime_, 
        uint256 playEndTime_) 
        Ownable() {
        // Commission cannot be higher than 30%
        if (commissionPercentage_ > MAX_OWNER_COMMISSION_PERCENTAGE) revert CommissionPercentageTooHigh();

        // Pool price cannot be zero
        if (poolPrice_ == 0) revert PoolPriceCannotBeZero(); 

        // Withdraw address cannot be zero address
        if (withdrawAddress_ == address(0)) revert WithdrawAddressCannotBeZeroAddress();

        _canJoinPool = canJoinPool_;
        i_poolPrice = poolPrice_;
        _withdrawAddress = withdrawAddress_;
        i_commissionPercentage = commissionPercentage_;

        // Enroll start time cannot be less than now
        i_enrollStartTime = enrollStartTime_ < block.timestamp ? block.timestamp : enrollStartTime_;

        // Play end time cannot be less than 10 minutes from now
        i_playEndTime = playEndTime_ < block.timestamp + 10 minutes ? block.timestamp + 10 minutes : playEndTime_;

        i_claimExpiryTime = playEndTime_ + CLAIM_EXPIRY_TIME;
    }

    /**
     * @dev Restricts actions to the enrollment phase, as defined by `i_enrollStartTime` and `i_playEndTime`.
     */
    modifier enrollPhase() {
        // Check if within enrollment/playtime
        if (block.timestamp < i_enrollStartTime || block.timestamp > i_playEndTime) revert EnrollmentPhaseInactive();
        _;
    }

    /**
     * @dev Restricts actions to after the end of the playtime phase.
     */
    modifier afterPlaytimePhase() {
        if (block.timestamp <= i_playEndTime) revert PlaytimeNotOver();
        _;
    }

    /**
     * @dev Restricts actions to before `i_claimExpiryTime`, indicating the active claim phase.
     */
    modifier claimPhase() {
        if (block.timestamp > i_claimExpiryTime) revert ClaimPhaseOver();
        _;
    }

    /**
     * @dev Allows owner to change the withdrawal address.
     */
    function updateWithdrawAddress(address payable newWithdrawAddress) external onlyOwner {
        if (newWithdrawAddress == address(0)) revert WithdrawAddressCannotBeZeroAddress();
        _withdrawAddress = newWithdrawAddress;

        emit WithdrawAddressUpdated(newWithdrawAddress);
    }

    /**
     * @dev Allows the owner to enable or disable pool intake during the enrollment phase.
     *
     * - `value` must not match the current `_canJoinPool` status.
     * - If `value` is `true`, `_refundActivated` must be `false`.
     */
    function enableJoinPool(bool value) external onlyOwner enrollPhase {
        // Check refund state
        if (value == true && _refundActivated) revert RefundInPlace();

        // Check merkle root is not set
        if (value == true && _prizeMerkleRoot != bytes32(0)) revert PrizeStructureInPlace();

        if (_canJoinPool == value) revert PoolIntakeAlreadySetTo(value);

        _canJoinPool = value;

        emit PoolIntakeEnabled(value);
    }

    /**
     * @dev Allows the owner to enable refund mode during the claim phase, deactivating pool intake.
     *
     * - `_refundActivated` must be `false`.
     * - `_prizeMerkleRoot` must not be set (indicating no prize structure in place).
     */
    function enableRefund() external virtual onlyOwner claimPhase {
        if (_refundActivated) revert RefundInPlace();

        // Check merkle root is not set
        if (_prizeMerkleRoot != bytes32(0)) revert PrizeStructureInPlace();

        _canJoinPool = false;
        _refundActivated = true;

        emit RefundEnabled();
    }

    /**
     * @dev Allows the owner to disable refund mode, optionally re-enabling pool intake.
     *
     * - `_refundActivated` must be `true`.
     * - `_refundClaimCount` must be zero.
     */
    function disableRefund(bool canJoinPool) external virtual onlyOwner {
        if (!_refundActivated) revert RefundAlreadyInactive();

        if (_refundClaimCount > 0) revert RefundCountNotZero(_refundClaimCount);

        _canJoinPool = canJoinPool;
        _refundActivated = false;

        emit RefundDisabled();
    }

    /**
     * @dev Sets the Merkle root for prize claims during the claim phase and disables pool intake.
     *
     * - `i_playEndTime` must have passed.
     * - `_refundActivated` must be `false`.
     */
    function setPrizeMerkleRoot(bytes32 merkleRoot) public virtual onlyOwner claimPhase afterPlaytimePhase {
        // Check refund is not activated
        if (_refundActivated) revert RefundInPlace();

        // merkle root cannot be zero
        if (merkleRoot == bytes32(0)) revert MerkleRootCannotBeZero();

        // Disable join pool bool
        _canJoinPool = false;

        // Record balance after playtime, so we can calculate commission
        _balanceAfterPlaytime = getContractBalance();

        _prizeMerkleRoot = merkleRoot;

        emit MerkleRootSet(merkleRoot);
    }

    /**
     * @dev Allows users to purchase a join the pool during the enrollment phase.
     *
     * - `_canJoinPool` must be true.
     * - Caller must not already be in the pool.
     * - The amount paid is checked to be equal to `i_poolPrice` in _validateAmountPaid().
     */
    function joinPool() external payable enrollPhase nonReentrant {
        // Check can join pool
        if (!_canJoinPool) revert PoolIntakeInactive();

        // Check if user has already joined
        if (_participantRecorded[msg.sender]) revert UserAlreadyInPool();

        // Check if amount paid/allowed is correct
        _validateAmountPaid(i_poolPrice);

        // Count unique participant
        unchecked {
            _uniqueParticipants++;
        }

        // Record participant
        _participantRecorded[msg.sender] = true;

        emit PoolJoined(msg.sender);

        // transfer tokens, if applicable
        _sendTokenOnJoinPool(i_poolPrice);
    }

    /**
     * @dev Allows users to claim their prize by providing proof that is verified in the merkleRoot.
     *
     * - `_prizeMerkleRoot` must be set.
     * - Caller must not have already claimed their prize.
     */
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
        _sendPrize(amount);
    }

    /**
     * @dev Allows users to claim a refund if the refund process is active.
     *
     * - `_refundActivated` must be true.
     * - Caller must not have already claimed a refund.
     * - Calculated `refundAmount` must be greater than zero, based on the caller’s enrolled tiers.
     */
    function claimRefund() external virtual claimPhase nonReentrant {
        // Ensure refund process is activated
        if (!_refundActivated) revert RefundInactive();

        // Check if user has already claimed
        if (_refundClaims[msg.sender]) revert RefundAlreadyClaimed(msg.sender);

        // Check if user is in pool
        if (!_participantRecorded[msg.sender]) revert UserNotInPool(msg.sender);

        // Mark refund as claimed
        _refundClaims[msg.sender] = true;
        unchecked {
            _refundClaimCount++;
        }

        emit RefundClaimed(msg.sender, i_poolPrice);

        // Send refund
        _sendRefund(i_poolPrice);
    }

    /**
     * @dev Allows owner to claim commission after playtime is over and merkle root is set.
     *
     * - `_prizeMerkleRoot` must be set.
     * - Caller must not have already claimed the commission.
     * - Commission goes to withdrawal address
     */
    function claimOwnerCommission() external virtual onlyOwner afterPlaytimePhase {
        // Owner can claim only after the prize structure is in place
        if (_prizeMerkleRoot == bytes32(0)) revert PrizeStructureNotSet();

        // Check if already claimed
        if (_commissionClaimed) revert CommissionAlreadyClaimed();

        // Check commission amount
        uint256 commissionAmount = getCurrentCommission();
        if (commissionAmount == 0) revert NoCommissionToClaim();

        _commissionClaimed = true;

        emit OwnerCommissionClaimed(_withdrawAddress, commissionAmount);

       _sendOwnerCommission(commissionAmount);
    }

    /**
     * @dev Allows the contract owner to withdraw unclaimed prizes if the claim condition is met.
     *
     * Requirements:
     * - The contract must hold a non-zero balance of unclaimed prizes.
     * - The withdrawn amount goes to the withdrawal address, not to the owner
     */
    function withdrawUnclaimedPrizes() external onlyOwner {
         // Check expiry time
        if (block.timestamp < i_claimExpiryTime) {
            revert ClaimExpiryTimeNotReached();
        }

        // Determine the balance of the contract
        uint256 balance = getContractBalance();

        // Ensure there is a balance to withdraw
        if (balance == 0) revert NoUnclaimedPrizes();

        emit UnclaimedPrizesWithdrawn(balance);

        // Withdraw unclaimed prizes based on token type
        _sendUnclaimedPrizes(balance);
    }

    /**
     * @dev Checks if the amount paid is correct.
     */
    function _validateAmountPaid(uint256 amount) internal virtual;

    /**
     * @dev Function used to send the tokens to the contract during pool joining, needed for ERC20 pools.
     *
     */
    function _sendTokenOnJoinPool(uint256 amount) internal virtual;

     /**
     * @dev Function used for the prize sending transaction.
     */   
    function _sendPrize(uint256 amount) internal virtual;

    /**
     * @dev Function used for the refund sending transaction.
     */
    function _sendRefund(uint256 refundAmount) internal virtual;

    /**
     * @dev Function used for the owner commission sending transaction.
     */
    function _sendOwnerCommission(uint256 commissionAmount) internal virtual;

    /**
     * @dev Function used for the unclaimed prizes sending transaction.
     */
    function _sendUnclaimedPrizes(uint256 balance) internal virtual;



    /**
     * GETTERS
     */

    /**
     * @dev Returns the current balance of the contract. For example: ETH or ERC20
     *
     * This function should be overridden in child contracts.
     */
    function getContractBalance() public view virtual returns (uint256);

    function getCanJoinPool() public view returns (bool) {
        return _canJoinPool;
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

    function getPoolPrice() public view returns (uint256) {
        return i_poolPrice;
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
            return i_commissionPercentage * getContractBalance() / 100;
        } else {
            return i_commissionPercentage * _balanceAfterPlaytime / 100;
        }
    }

    function getCommissionClaimed() public view returns (bool) {
        return _commissionClaimed;
    }

    function getCommissionPercentage() public view returns (uint8) {
        return i_commissionPercentage;
    }
}