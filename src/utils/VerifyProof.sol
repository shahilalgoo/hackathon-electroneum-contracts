// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

library VerifyProof {
    error InvalidProof(address who);

    /**
     * @dev Verifies a Merkle proof for the given amount associated with the caller's address.
     *
     * This function:
     * - Creates a Merkle tree leaf node by hashing the caller's address and the provided amount.
     * - Checks the validity of the Merkle proof against the merkle root.
     * - Reverts with `InvalidProof` if the proof is invalid.
     *
     * @param proof The Merkle proof, an array of bytes32 values for verification.
     * @param amount The amount linked to the caller's address within the Merkle tree.
     * @param root The Merkle root.
     */
    function verify(
        bytes32[] calldata proof,
        uint256 amount,
        bytes32 root
    ) internal view {
        // Create leaf
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender, amount)))
        );

        // Verify the Merkle proof
        if (!MerkleProof.verify(proof, root, leaf))
            revert InvalidProof(msg.sender);
    }
}
