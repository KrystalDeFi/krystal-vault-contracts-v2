// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISharedStrategy {
  error InvalidPoolTokens();

  /// @dev Shared strategies validate pool currencies against SharedVault's ERC20 token set.
  ///      Because vault token slots use `address(0)` as "unused", native-currency V4/Pancake pools
  ///      where a currency unwraps to `address(0)` are unsupported. Use wrapped-native ERC20 pools.
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
  /// @param data ABI-encoded operation (strategy-specific). V3-style shared strategies (`SharedV3Strategy`,
  ///        `SharedAerodromeStrategy`) use `IV3Utils`-compatible structs but execute natively in the strategy.
  ///        `SharedV4Strategy` and `SharedPancakeV4Strategy` accept protocol-specific V4Utils-compatible
  ///        instructions and execute them natively through the relevant PositionManager. Utility fee fields remain
  ///        API-controlled; platform and owner fees are read from shared-vault config and vault state.
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
  /// @param vaultOwnerFeeBasisPoint Deprecated compatibility argument. Implementations must read vault-owner bps from the vault.
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

  /// @notice Add a proportional share of tokens to an existing LP position during vault deposit.
  /// @dev Called via delegatecall from SharedVault.deposit so address(this) is the vault.
  ///      Increases liquidity with the given amounts; tokens not consumed by the position
  ///      (due to price range mismatch) remain as idle vault balance automatically.
  ///      Implementations that cannot increase liquidity (e.g. MasterChef-staked positions)
  ///      MUST return silently — the caller leaves unused tokens as idle.
  /// @param nfpm NFT Position Manager (or V4 PositionManager) address
  /// @param tokenId Position NFT ID
  /// @param amount0 Max amount of token0 to add
  /// @param amount1 Max amount of token1 to add
  /// @param slippageBps Slippage tolerance in basis points (e.g. 100 = 1%). Applied as
  ///        amountMin = FullMath.mulDiv(amount, 10000 - slippageBps, 10000). Pass 0 for no floor.
  function depositProportional(
    address nfpm,
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1,
    uint16 slippageBps
  ) external;

  /// @notice Get token amounts for a tracked LP position (liquidity + uncollected fees)
  /// @dev Called via regular CALL (not staticcall) from non-view vault functions such as deposit().
  ///      The function is declared `view` so Solidity prevents state mutation, but the EVM opcode
  ///      used by the caller is CALL, not STATICCALL, when invoked from a non-view context.
  /// @param nfpm NFT Position Manager address
  /// @param tokenId Position NFT ID
  /// @return amount0 Amount of token0 in the position
  /// @return amount1 Amount of token1 in the position
  function getPositionAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);

  /// @notice Return the canonical token pair for an LP position as recorded on-chain by the NFPM/POSM.
  /// @dev Used by SharedVault.recoverPosition to validate operator-supplied token0/token1 against the
  ///      actual pool, preventing metadata mismatch that could misprice deposits/withdrawals.
  ///      Called via regular external CALL (not delegatecall) so address(this) is the strategy.
  /// @param nfpm NFT Position Manager (or V4 PositionManager) address
  /// @param tokenId Position NFT ID
  /// @return token0 Canonical pool token0 address
  /// @return token1 Canonical pool token1 address
  function getPositionTokens(address nfpm, uint256 tokenId) external view returns (address token0, address token1);

  /// @notice Collect accumulated LP fees into vault idle balance and settle performance/platform fees.
  /// @dev Called via delegatecall from SharedVault.withdraw() BEFORE the idle-balance snapshot. Strategy execute
  ///      paths also call their internal collect logic before mutating an existing position. Implementations
  ///      should collect fees from the NFPM/POSM and take performance + platform fees via the appropriate
  ///      fee mechanism.
  /// @param nfpm NFT Position Manager (or V4 PositionManager) address
  /// @param tokenId Position NFT ID
  /// @param vaultOwnerFeeBasisPoint Deprecated compatibility argument. Implementations must read vault-owner bps from the vault.
  function collectFees(address nfpm, uint256 tokenId, uint16 vaultOwnerFeeBasisPoint) external;

  /// @notice Get *principal-only* token amounts for a tracked LP position, excluding uncollected fees/rewards.
  /// @dev Returns the token amounts computed purely from the position's in-range liquidity at the current price.
  ///      This is the correct ratio for topping up an existing position via `increaseLiquidity` — uncollected
  ///      fees live in the NFPM as `tokensOwed*` and accrue in a ratio set by historical swap flow, NOT by
  ///      the current price range. Mixing them into the top-up desired amounts would make the
  ///      `amount0Desired : amount1Desired` ratio diverge from the range, so `increaseLiquidity` would either
  ///      (a) consume far less on the "off-ratio" side, leaving dust idle, or
  ///      (b) revert the slippage check when `amount*Min > 0` because the actually consumed amount on the
  ///          binding side falls below the `amount*Min` derived from the desired value.
  ///      SharedVault uses this function (not `getPositionAmounts`) when scaling per-depositor top-ups,
  ///      treating uncollected fees as idle vault balance for share-pricing purposes (they are still counted
  ///      in `getPositionAmounts`, which remains the total-value view).
  ///
  ///      Strategies that cannot meaningfully increase liquidity (e.g. staked / locked positions whose
  ///      `depositProportional` returns silently) MAY return (0, 0); the caller skips the LP top-up and
  ///      leaves tokens as idle.
  /// @param nfpm NFT Position Manager address
  /// @param tokenId Position NFT ID
  /// @return amount0 Principal-only amount of token0 (excludes uncollected fees/rewards)
  /// @return amount1 Principal-only amount of token1 (excludes uncollected fees/rewards)
  function getPositionPrincipalAmounts(
    address nfpm,
    uint256 tokenId
  ) external view returns (uint256 amount0, uint256 amount1);
}
