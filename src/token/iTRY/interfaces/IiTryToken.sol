// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title IiTryToken
 * @notice Interface for the iTRY token contract
 * @dev This interface defines the functions that the iTryIssuer contract needs to interact with the iTRY token
 */
interface IiTryToken is IERC20, IERC20Permit, IERC20Metadata {
    /**
     * @notice Mint new iTRY tokens
     * @param to The address to receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn iTRY tokens from a specific address
     * @param from The address whose tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) external;
}
