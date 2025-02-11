// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

library VerifyProof {
    error InvalidProof(address who);
    
    function verify(bytes32[] calldata proof, uint256 amount, bytes32 root) internal view {
        // Create leaf
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));

        // Verify the Merkle proof
        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidProof(msg.sender);
    }
}