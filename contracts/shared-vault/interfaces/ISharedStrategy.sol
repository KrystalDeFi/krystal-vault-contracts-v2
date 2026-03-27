// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedStrategy {
  error InvalidPoolTokens();

  struct PositionChange {
    bool isAdd; // true = new position, false = position removed
    address nfpm; // NFT Position Manager address
    uint256 tokenId; // Position NFT ID
    address token0; // Pool token0
    address token1; // Pool token1
  }

  /// @notice Execute an LP operation. Called via delegatecall from SharedVault.
  /// @dev Strategy MUST validate that pool tokens are vault tokens by calling
  ///      ISharedVault(address(this)).isVaultToken(token) for each pool token.
  ///      Since this runs via delegatecall, address(this) is the vault.
  ///      Strategy MUST return position changes so the vault can track LP positions.
  /// @param data Encoded operation params (strategy-specific)
  /// @return changes Array of position changes (added/removed)
  function execute(bytes calldata data) external payable returns (PositionChange[] memory changes);

  /// @notice Get token amounts for a tracked LP position (liquidity + uncollected fees)
  /// @dev Called via regular staticcall from the vault. Strategy uses its own
  ///      protocol-specific interfaces for precise valuation.
  /// @param nfpm NFT Position Manager address
  /// @param tokenId Position NFT ID
  /// @return amount0 Amount of token0 in the position
  /// @return amount1 Amount of token1 in the position
  function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);
}
