// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import { ISharedStrategy } from "../interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../interfaces/ISharedVault.sol";
import { ISharedCommon } from "../interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../interfaces/ISharedConfigManager.sol";
import { SharedStrategyGuards } from "../libraries/SharedStrategyGuards.sol";
import { IFeeTaker } from "../../public-vault/interfaces/strategies/IFeeTaker.sol";
import { SharedStrategyFeeConfig } from "../libraries/SharedStrategyFeeConfig.sol";
import { SharedV4StrategyLib } from "../libraries/SharedV4StrategyLib.sol";
import { SharedV4ValuationLib } from "../libraries/SharedV4ValuationLib.sol";
import { ISharedV4Utils } from "../interfaces/ISharedV4Utils.sol";

/// @title SharedV4Strategy
/// @notice Uniswap V4 LP operations for SharedVault with token validation and position tracking
contract SharedV4Strategy is ISharedStrategy, IFeeTaker {
  address public immutable swapRouter;

  enum OperationType {
    EXECUTE,
    /// @dev Historically named `SAFE_TRANSFER_NFT`; the NFT no longer moves — the strategy
    ///      executes the encoded instruction bytes inline via the lib. Renamed for clarity.
    EXECUTE_INSTRUCTIONS
  }

  constructor(address _swapRouter) {
    require(_swapRouter != address(0), ISharedCommon.ZeroAddress());
    swapRouter = _swapRouter;
  }

  /// @inheritdoc ISharedStrategy
  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    OperationType opType = abi.decode(data[:32], (OperationType));

    if (opType == OperationType.EXECUTE) return _execute(data[32:]);
    else if (opType == OperationType.EXECUTE_INSTRUCTIONS) return _executeInstructions(data[32:]);
    else revert ISharedCommon.InvalidOperation();
  }

  /// @dev `approveTokens` / `approveAmounts` are kept for ABI backward-compatibility but are NOT
  ///      used for ERC20 approvals. Approvals are issued per-hop inside `SharedV4SwapPipeline._swap`
  ///      against the immutable `swapRouter` (and to the POSM via Permit2 in `SharedV4StrategyLib`).
  ///      `approveTokens` is still walked by `_validateApprovalList` to enforce that EVERY entry
  ///      references a vault-tracked token (including zero-amount entries), preventing operators
  ///      from listing unrelated tokens through this entry point.
  function _execute(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (
      address posm,
      uint256 tokenId,
      bytes memory params,
      uint256 ethValue,
      address[] memory approveTokens,
      uint256[] memory approveAmounts
    ) = abi.decode(data, (address, uint256, bytes, uint256, address[], uint256[]));

    ISharedConfigManager cm = ISharedVault(address(this)).configManager();
    SharedStrategyGuards.requireWhitelistedNfpm(cm, posm);
    require(approveTokens.length == approveAmounts.length, ISharedCommon.LengthMismatch());
    bytes4 selector = _v4ParamsSelector(params);
    _validateApprovalList(approveTokens);
    require(ethValue == 0, ISharedCommon.InvalidAmount());
    bool isExecute = selector == ISharedV4Utils.execute.selector;
    bool isSwapAndMint = selector == ISharedV4Utils.swapAndMint.selector;
    bool isSwapAndIncrease = selector == ISharedV4Utils.swapAndIncrease.selector;
    if (!isExecute && !isSwapAndMint && !isSwapAndIncrease) revert ISharedCommon.InvalidOperation();

    IPositionManager pm = IPositionManager(posm);

    // Snapshot next tokenId before the call to detect newly minted positions
    uint256 nextIdBefore = pm.nextTokenId();

    if (isExecute) {
      require(tokenId != 0, ISharedCommon.InvalidOperation());
      SharedV4StrategyLib.executeCalldata(swapRouter, posm, tokenId, params);
    } else if (isSwapAndMint) {
      require(tokenId == 0, ISharedCommon.InvalidOperation());
      SharedV4StrategyLib.swapAndMintCalldata(swapRouter, posm, params);
    } else {
      require(tokenId != 0, ISharedCommon.InvalidOperation());
      SharedV4StrategyLib.swapAndIncreaseCalldata(swapRouter, posm, tokenId, params);
    }

    // Compute position changes from on-chain state — never trust caller-supplied values
    if (tokenId == 0) {
      // New mint: require exactly one position was minted to avoid untracked vault positions.
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      uint256 newId = nextIdBefore;
      require(_posmNftOwnedByVault(posm, newId), InvalidPoolTokens());
      (PoolKey memory key,) = pm.getPoolAndPositionInfo(newId);
      (address c0, address c1) = _poolVaultTokens(key.currency0, key.currency1);
      _validateVaultToken(c0);
      _validateVaultToken(c1);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(true, posm, newId, c0, c1);
    } else if (
      pm.nextTokenId() > nextIdBefore && _posmNftOwnedByVault(posm, nextIdBefore)
        && pm.getPositionLiquidity(tokenId) == 0
    ) {
      // ADJUST_RANGE: require exactly one new position so no vault-owned NFTs go untracked.
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      (PoolKey memory oldKey,) = pm.getPoolAndPositionInfo(tokenId);
      (PoolKey memory newKey,) = pm.getPoolAndPositionInfo(nextIdBefore);
      // F18: validate the new range's currencies too (symmetry with the tokenId==0 mint branch);
      // defense-in-depth on top of the vault's own _applyPositionChanges checks.
      (address old0, address old1) = _poolVaultTokens(oldKey.currency0, oldKey.currency1);
      (address new0, address new1) = _poolVaultTokens(newKey.currency0, newKey.currency1);
      _validateVaultToken(new0);
      _validateVaultToken(new1);
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, posm, tokenId, old0, old1);
      changes[1] = PositionChange(true, posm, nextIdBefore, new0, new1);
    } else if (pm.getPositionLiquidity(tokenId) == 0) {
      // Full exit: liquidity drained to zero
      (PoolKey memory key,) = pm.getPoolAndPositionInfo(tokenId);
      (address c0, address c1) = _poolVaultTokens(key.currency0, key.currency1);
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, posm, tokenId, c0, c1);
    } else {
      // Partial decrease, compound, or increase — must NOT have minted a new vault-owned NFT
      require(pm.nextTokenId() == nextIdBefore || !_posmNftOwnedByVault(posm, nextIdBefore), InvalidPoolTokens());
      changes = new PositionChange[](0);
    }
  }

  /// @dev Executes the encoded instruction bytes inline against the position; despite the
  ///      historical name `SAFE_TRANSFER_NFT`, the NFT itself is never transferred — the strategy
  ///      operates on the position in-place via the shared lib.
  function _executeInstructions(bytes calldata data) internal returns (PositionChange[] memory changes) {
    (address posm, uint256 tokenId, bytes memory instruction) = abi.decode(data, (address, uint256, bytes));

    _requireWhitelistedPosm(posm);

    IPositionManager pm = IPositionManager(posm);

    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(tokenId);
    (address c0, address c1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);
    _validateVaultToken(c0);
    _validateVaultToken(c1);
    uint256 nextIdBefore = pm.nextTokenId();

    SharedV4StrategyLib.executeInstructionBytes(swapRouter, posm, tokenId, instruction);

    if (
      pm.nextTokenId() > nextIdBefore && _posmNftOwnedByVault(posm, nextIdBefore)
        && pm.getPositionLiquidity(tokenId) == 0
    ) {
      require(pm.nextTokenId() == nextIdBefore + 1, InvalidPoolTokens());
      (PoolKey memory newKey,) = pm.getPoolAndPositionInfo(nextIdBefore);
      // F18: validate the new range's currencies (symmetry / defense-in-depth).
      (address new0, address new1) = _poolVaultTokens(newKey.currency0, newKey.currency1);
      _validateVaultToken(new0);
      _validateVaultToken(new1);
      changes = new PositionChange[](2);
      changes[0] = PositionChange(false, posm, tokenId, c0, c1);
      changes[1] = PositionChange(true, posm, nextIdBefore, new0, new1);
    } else if (!_posmNftOwnedByVault(posm, tokenId) || pm.getPositionLiquidity(tokenId) == 0) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange(false, posm, tokenId, c0, c1);
    } else {
      require(pm.nextTokenId() == nextIdBefore || !_posmNftOwnedByVault(posm, nextIdBefore), InvalidPoolTokens());
      changes = new PositionChange[](0);
    }
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Uses `INCREASE_LIQUIDITY` + `CLOSE_CURRENCY` so the PositionManager pulls the exact
  ///      amounts required for the computed liquidity through Permit2. Any amount not needed for
  ///      the current pool/range ratio stays idle in the vault. Permit2 approval is set inline.
  ///      Slippage is enforced via a per-token consumed-amount floor (NOT a liquidity comparison):
  ///      the lib quotes `(expected0, expected1) = getAmountsForLiquidity(...)` for the computed
  ///      liquidity at the pre-call sqrtPrice, measures the amounts ACTUALLY consumed via balance
  ///      deltas, and reverts unless `used0 >= expected0 * (1 - slippageBps/10000)` and likewise for
  ///      token1. Quoting the floor from `getAmountsForLiquidity` (not the raw supplied amounts) lets
  ///      single-sided / out-of-range adds pass without spurious reverts. NOTE: adding CL liquidity
  ///      does not move the spot price, so within one tx `used == expected`; this floor catches a
  ///      misbehaving position manager but cannot by itself defeat a CROSS-transaction sandwich —
  ///      callers must pass a conservative `slippageBps` and derive the deposit ratio externally.
  function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps)
    external
    override
  {
    SharedV4StrategyLib.depositProportional(posm, tokenId, amount0, amount1, slippageBps);
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Collects accumulated fees via DECREASE_LIQUIDITY(0) + TAKE_PAIR — a zero-liquidity
  ///      decrease syncs fee growth without touching principal; TAKE_PAIR sweeps accumulated fees
  ///      to the vault (address(this) in delegatecall context). Performance and platform fees are
  ///      then applied inline since V4Strategy has no dedicated lpFeeTaker.
  ///      Native-currency pool amounts are accounted against the vault's configured WETH token.
  function collectFees(
    address posm,
    uint256 tokenId,
    uint16 /* vaultOwnerFeeBasisPoint */
  )
    external
    override
  {
    SharedV4StrategyLib.collectFees(posm, tokenId, SharedStrategyFeeConfig.performanceFeeConfig());
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Withdraw exits collect generated LP fees through collectFees() before the vault's idle snapshot.
  ///      This function only decreases principal natively and never charges platform/owner fees on principal.
  function exitProportional(
    address posm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256 minAmount0,
    uint256 minAmount1,
    uint16 /* vaultOwnerFeeBasisPoint */
  ) external override returns (PositionChange[] memory changes) {
    changes = SharedV4StrategyLib.exitProportional(posm, tokenId, shares, totalShares, minAmount0, minAmount1);
  }

  /// @inheritdoc ISharedStrategy
  /// @dev Values principal liquidity via `LiquidityAmounts` and current `sqrtPrice` from the v4 PoolManager,
  ///      and uncollected fees via the same `StateLibrary` + fee-growth pattern as v4utils tests (FeeMath).
  ///      Same external-call pattern as `SharedV3Strategy` / Aerodrome / Pancake `getPositionAmounts`:
  ///      no POSM whitelist here; POSM allowlist is enforced on delegatecall paths and when the vault tracks positions.
  function getPositionAmounts(address posm, uint256 tokenId)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    (amount0, amount1) = SharedV4ValuationLib.getPositionAmounts(posm, tokenId);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionTokens(address posm, uint256 tokenId)
    external
    view
    override
    returns (address token0, address token1)
  {
    (PoolKey memory poolKey,) = IPositionManager(posm).getPoolAndPositionInfo(tokenId);
    (token0, token1) = _poolVaultTokens(poolKey.currency0, poolKey.currency1);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionPrincipalAmounts(address posm, uint256 tokenId)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    (amount0, amount1) = SharedV4ValuationLib.getPositionPrincipalAmounts(posm, tokenId);
  }

  /// @inheritdoc ISharedStrategy
  function getPositionAmountsSplit(address posm, uint256 tokenId)
    external
    view
    override
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    (total0, total1, principal0, principal1) = SharedV4ValuationLib.getPositionAmountsSplit(posm, tokenId);
  }

  function _posmNftOwnedByVault(address posm, uint256 id) private view returns (bool) {
    try IERC721(posm).ownerOf(id) returns (address owner) {
      return owner == address(this);
    } catch {
      return false;
    }
  }

  function _validateVaultToken(address token) internal view {
    require(ISharedVault(address(this)).isVaultToken(token), InvalidPoolTokens());
  }

  function _poolVaultTokens(Currency currency0, Currency currency1)
    private
    view
    returns (address token0, address token1)
  {
    token0 = _vaultToken(currency0);
    token1 = _vaultToken(currency1);
    require(token0 != token1, InvalidPoolTokens());
  }

  function _vaultToken(Currency currency) private view returns (address token) {
    token = Currency.unwrap(currency);
    if (token == address(0)) token = _contextWeth();
  }

  function _contextWeth() private view returns (address weth) {
    if (msg.sender.code.length > 0) {
      try ISharedVault(msg.sender).weth() returns (address callerWeth) {
        return callerWeth;
      } catch { }
    }
    if (address(this).code.length > 0) {
      try ISharedVault(address(this)).weth() returns (address selfWeth) {
        return selfWeth;
      } catch { }
    }
  }

  function _requireWhitelistedPosm(address posm) private view {
    SharedStrategyGuards.requireWhitelistedNfpm(ISharedVault(address(this)).configManager(), posm);
  }

  /// @dev Validates EVERY listed token unconditionally — including zero-amount entries. The list is
  ///      vestigial (never used to issue approvals), so this is defense-in-depth: it keeps the entry
  ///      point honest if a future change ever reads `approveTokens`. Array-length consistency is
  ///      enforced by the caller before this runs.
  function _validateApprovalList(address[] memory approveTokens) private view {
    for (uint256 i; i < approveTokens.length;) {
      _validateVaultToken(approveTokens[i]);
      unchecked {
        i++;
      }
    }
  }

  function _v4ParamsSelector(bytes memory params) private pure returns (bytes4 selector) {
    require(params.length >= 4, ISharedCommon.InvalidOperation());
    selector = bytes4(params);
  }
}
