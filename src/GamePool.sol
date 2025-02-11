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

    // Modifier Errors
    error EnrollmentPhaseInactive();
    error PlaytimeOver();
    error PlaytimeNotOver();
    error ClaimPhaseOver();

    // Buy Ticket Errors
    error TicketSaleInactive();
    error UserAlreadyHasTicket();
    error AmountPaidInvalid(uint256 paid, uint256 price);

    // Claim Errors
    error PrizeStructureNotSet();
    error UserAlreadyClaimed(address user);
    error PrizeTransferFailed(address recipient);

    
    // Unclaimed Withdrawal Errors
    error UnclaimedPrizesTransferFailed();
    error ClaimExpiryTimeNotReached();
    error NoUnclaimedPrizes();

    /**
     * CONSTANTS/IMMUTABLES
     */
    uint256 private constant CLAIM_EXPIRY_TIME = 30 days;
    uint256 private immutable i_enrollStartTime;
    uint256 private immutable i_playEndTime;
    uint256 private immutable i_claimExpiryTime;
    uint256 private immutable i_ticketPrice;
    address payable immutable i_withdrawAddress;

    /**
     * STATE VARIABLES
     */
    bool private _canBuyTicket;
    uint32 private _uniqueParticipants;
    bytes32 private _prizeMerkleRoot;
    uint32 private _prizeClaimCount;

    mapping(address => bool) private _participantRecorded;
    mapping(address => bool) private _prizeClaims;

    /**
     * EVENTS
     */
    event TicketBought(address indexed participant);
    event PrizeClaimed(address indexed participant, uint256 amount);
    event UnclaimedPrizesWithdrawn(uint256 amount);


    constructor(
        bool canBuyTicket_, 
        uint256 ticketPrice_,
        address payable withdrawAddress_,
        uint256 enrollStartTime_, 
        uint256 playEndTime_) 
        Ownable() {
        // Withdraw address cannot be zero address
        if (withdrawAddress_ == address(0)) revert WithdrawAddressCannotBeZeroAddress();

        _canBuyTicket = canBuyTicket_;
        i_ticketPrice = ticketPrice_;

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
        (bool success,) = i_withdrawAddress.call{value: balance}("");
        if (!success) revert UnclaimedPrizesTransferFailed();
    }



    /**
     * GETTERS
     */

    function getCanBuyTicket() public view returns (bool) {
        return _canBuyTicket;
    }

    function getWithdrawAddress() public view returns (address) {
        return i_withdrawAddress;
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
}