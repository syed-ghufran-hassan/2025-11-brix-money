// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// SigUtils - Signature utility for EIP-712 permits and similar functionality
// Compatible with OpenZeppelin v4.9.2 ERC20Permit and similar contracts
contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // EIP-712 Domain Separator
    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    // Generic hash function for permit structures
    function hashTypedData(bytes32 structHash) external view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    // Permit message hash for ERC20Permit
    function getStructHash(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        external
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
    }
}
