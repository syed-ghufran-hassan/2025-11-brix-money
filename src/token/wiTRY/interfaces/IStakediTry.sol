// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface IStakediTry {
    // Events //
    /// @notice Event emitted when the rewards are received
    event RewardsReceived(uint256 amount);
    /// @notice Event emitted when the balance from an FULL_RESTRICTED_STAKER_ROLE user are redistributed
    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);
    /// @notice Event emitted when the vesting period is updated
    event VestingPeriodUpdated(uint256 indexed oldVestingPeriod, uint256 indexed newVestingPeriod);

    // Errors //
    /// @notice Error emitted shares or assets equal zero.
    error InvalidAmount();
    /// @notice Error emitted when owner attempts to rescue iTry tokens.
    error InvalidToken();
    /// @notice Error emitted when a small non-zero share amount remains, which risks donations attack
    error MinSharesViolation();
    /// @notice Error emitted when owner is not allowed to perform an operation
    error OperationNotAllowed();
    /// @notice Error emitted when there is still unvested amount
    error StillVesting();
    /// @notice Error emitted when owner or blacklist manager attempts to blacklist owner
    error CantBlacklistOwner();
    /// @notice Error emitted when the zero address is given
    error InvalidZeroAddress();
    /// @notice Error emitted when an invalid vesting period is provided
    error InvalidVestingPeriod();

    function transferInRewards(uint256 amount) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function getUnvestedAmount() external view returns (uint256);

    function setVestingPeriod(uint256 _vestingPeriod) external;

    function getVestingPeriod() external view returns (uint256);
}
