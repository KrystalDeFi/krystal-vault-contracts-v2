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
  /// @dev Strategy MUST validate that pool tokens are vault tokens.
  ///      Since this runs via delegatecall, address(this) is the vault.
  /// @param data Encoded operation params (strategy-specific). V3-style strategies append
  ///        `(uint16 platformFeeBps, uint64 gasFeeX64)` after swap/mint, swap/increase, and safe-transfer payloads.
  ///        Platform `0` uses `configManager.platformFeeBasisPoint()`; gas is used as passed.
  /// @return changes Array of position changes (added/removed)
  function execute(bytes calldata data) external payable returns (PositionChange[] memory changes);

  /// @notice Exit a proportional share of an LP position during vault withdrawal.
  /// @dev Called via delegatecall from SharedVault.withdraw so address(this) is the vault.
  ///      Must remove `shares/totalShares` of the position's liquidity, collect fees,
  ///      and leave resulting tokens in the vault. Returns position changes so the vault
  ///      can untrack the position if fully exited.
  /// @param nfpm NFT Position Manager
  /// @param tokenId Position NFT ID
  /// @param shares Withdrawer's share count
  /// @param totalShares Total vault share supply (snapshot before burn)
  /// @param minAmount0 Minimum token0 to receive (slippage guard)
  /// @param minAmount1 Minimum token1 to receive (slippage guard)
  /// @param vaultOwnerFeeBasisPoint Vault owner bps for this exit; platform fee from `configManager`. No gas fee on withdraw exits.
  /// @return changes Empty if partial exit; single removal entry if fully exited
  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 vaultOwnerFeeBasisPoint
  ) external returns (PositionChange[] memory changes);

  /// @notice Get token amounts for a tracked LP position (liquidity + uncollected fees)
  /// @dev Called via regular staticcall from the vault.
  /// @param nfpm NFT Position Manager address
  /// @param tokenId Position NFT ID
  /// @return amount0 Amount of token0 in the position
  /// @return amount1 Amount of token1 in the position
  function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);
}
