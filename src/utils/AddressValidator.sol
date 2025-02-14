// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
library AddressValidator {
    
    error InvalidTokenAddress();

    /**
     * @dev Validates that a given ERC20 token address is a valid contract address.
     *
     * This function:
     * - Checks that the address contains deployed code, indicating it is a contract.
     * - Attempts to call a function 'unique' to ERC20 contracts (`allowance`), reverting with
     *   `InvalidTokenAddress` if the address is not a valid ERC20 token.
     *
     * @param erc20tokenAddress_ The address of the ERC20 token to validate.
     *
     * IMPORTANT: The function will succeed for any contract that has an 'allowance' function. Double check before setting the token address.
     */
    function ERC20Check(address erc20tokenAddress_) internal view {
        codeSizeCheck(erc20tokenAddress_);

        // Check a function 'unique' to ERC20 (zero code addresses do not return errors)
        try IERC20(erc20tokenAddress_).allowance(address(this), address(this)) returns (uint256) {}
        catch {
            revert InvalidTokenAddress();
        }
    }

    function codeSizeCheck(address tokenAddress_) internal view {
        // Check if token address has code (block zero code addresses)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(tokenAddress_)
        }
        if (codeSize == 0) revert InvalidTokenAddress();
    }
}