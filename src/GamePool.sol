// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GamePool is Ownable, ReentrancyGuard {
    /**
     * ERRORS
     */
    // Modifier Errors
    error EnrollmentPhaseInactive();

    // Buy Ticket Errors
    error TicketSaleInactive();
    error UserAlreadyHasTicket();
    error AmountPaidInvalid(uint256 paid, uint256 price);

    /**
     * CONSTANTS/IMMUTABLES
     */
    uint256 private immutable i_enrollStartTime;
    uint256 private immutable i_playEndTime;
    uint256 private immutable i_ticketPrice;

    /**
     * STATE VARIABLES
     */
    bool private _canBuyTicket;
    uint32 internal _uniqueParticipants;

    mapping(address => bool) internal _participantRecorded;

    /**
     * EVENTS
     */
    event TicketBought(address indexed participant);

    constructor(bool canBuyTicket_, uint256 ticketPrice_, uint256 enrollStartTime_, uint256 playEndTime_) Ownable() {
        _canBuyTicket = canBuyTicket_;
        i_ticketPrice = ticketPrice_;
        i_enrollStartTime = enrollStartTime_;
        i_playEndTime = playEndTime_;
    }

    modifier enrollPhase() {
        // Check if within enrollment/playtime
        if (block.timestamp < i_enrollStartTime || block.timestamp > i_playEndTime) revert EnrollmentPhaseInactive();
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







    /**
     * GETTERS
     */
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getCanBuyTicket() public view returns (bool) {
        return _canBuyTicket;
    }

    function getEnrollStartTime() public view returns (uint256) {
        return i_enrollStartTime;
    }

    function getPlayEndTime() public view returns (uint256) {
        return i_playEndTime;
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
}