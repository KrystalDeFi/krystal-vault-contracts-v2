// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Fee-growth getters shared by Uniswap V3, its forks (PancakeSwap V3, Sushi V3) and Slipstream pools.
interface IFeeGrowthPool {
  function feeGrowthGlobal0X128() external view returns (uint256);
  function feeGrowthGlobal1X128() external view returns (uint256);
}

/// @dev `collect` as shared by the Uniswap V3 NFPM, its forks and the Slipstream NFPM.
interface IFeeCollectNfpm {
  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/// @notice Default fee settings for the shared-vault fork harnesses, plus the helpers their fee-accrual tests use.
/// @dev Every harness initializes its config manager with `DEFAULT_PLATFORM_FEE_BPS` and creates its vaults with
///      `DEFAULT_VAULT_OWNER_FEE_BPS`, so every path that charges performance fees runs with both fees on.
abstract contract SharedVaultFeeDefaults is Test {
  /// @dev Platform fee on realized LP fees (10%).
  uint16 internal constant DEFAULT_PLATFORM_FEE_BPS = 1000;
  /// @dev Vault-owner fee on realized LP fees (5%).
  uint16 internal constant DEFAULT_VAULT_OWNER_FEE_BPS = 500;

  uint256 private constant Q128 = 1 << 128;

  /// @dev Token balances of the platform fee recipient and of the vault owner.
  struct FeeRecipientBalances {
    uint256 platform0;
    uint256 platform1;
    uint256 owner0;
    uint256 owner1;
  }

  function _feeRecipientBalances(address token0, address token1, address platformRecipient, address vaultOwner_)
    internal
    view
    returns (FeeRecipientBalances memory balances)
  {
    balances.platform0 = IERC20(token0).balanceOf(platformRecipient);
    balances.platform1 = IERC20(token1).balanceOf(platformRecipient);
    balances.owner0 = IERC20(token0).balanceOf(vaultOwner_);
    balances.owner1 = IERC20(token1).balanceOf(vaultOwner_);
  }

  /// @dev Checks that since `before` the platform recipient and the vault owner received exactly their default
  ///      share of the realized LP fees `realized0` / `realized1`.
  function _assertFeeSplitPaid(
    FeeRecipientBalances memory before,
    address token0,
    address token1,
    address platformRecipient,
    address vaultOwner_,
    uint256 realized0,
    uint256 realized1
  ) internal view {
    FeeRecipientBalances memory current = _feeRecipientBalances(token0, token1, platformRecipient, vaultOwner_);
    assertEq(
      current.platform0 - before.platform0, realized0 * DEFAULT_PLATFORM_FEE_BPS / 10_000, "platform fee (token0)"
    );
    assertEq(
      current.platform1 - before.platform1, realized1 * DEFAULT_PLATFORM_FEE_BPS / 10_000, "platform fee (token1)"
    );
    assertEq(current.owner0 - before.owner0, realized0 * DEFAULT_VAULT_OWNER_FEE_BPS / 10_000, "owner fee (token0)");
    assertEq(current.owner1 - before.owner1, realized1 * DEFAULT_VAULT_OWNER_FEE_BPS / 10_000, "owner fee (token1)");
  }

  /// @dev Accrues LP fees without a swap by raising a V3-style pool's global fee growth: a position with
  ///      `liquidity` whose range holds the current tick earns about `fees0` / `fees1`. `feeGrowthSlot` is the
  ///      storage slot of `feeGrowthGlobal0X128`; `feeGrowthGlobal1X128` is the next slot. Both are checked
  ///      against the pool's getters first.
  function _accrueV3PoolFees(address pool, uint256 feeGrowthSlot, uint128 liquidity, uint256 fees0, uint256 fees1)
    internal
  {
    bytes32 slot0 = bytes32(feeGrowthSlot);
    bytes32 slot1 = bytes32(feeGrowthSlot + 1);
    uint256 growth0 = uint256(vm.load(pool, slot0));
    uint256 growth1 = uint256(vm.load(pool, slot1));
    assertEq(growth0, IFeeGrowthPool(pool).feeGrowthGlobal0X128(), "feeGrowthGlobal0X128 slot");
    assertEq(growth1, IFeeGrowthPool(pool).feeGrowthGlobal1X128(), "feeGrowthGlobal1X128 slot");
    uint256 bump0 = fees0 * Q128 / liquidity + 1;
    uint256 bump1 = fees1 * Q128 / liquidity + 1;
    unchecked {
      // Fee growth is a wrapping accumulator in the pool, so the bump wraps the same way.
      vm.store(pool, slot0, bytes32(growth0 + bump0));
      vm.store(pool, slot1, bytes32(growth1 + bump1));
    }
  }

  /// @dev The LP fees the NFPM would pay `owner` for `tokenId` right now: collects them as `owner` and rolls back.
  function _collectableV3Fees(address nfpm, uint256 tokenId, address owner)
    internal
    returns (uint256 fees0, uint256 fees1)
  {
    IFeeCollectNfpm.CollectParams memory params = IFeeCollectNfpm.CollectParams({
      tokenId: tokenId, recipient: owner, amount0Max: type(uint128).max, amount1Max: type(uint128).max
    });
    uint256 snapshot = vm.snapshotState();
    vm.prank(owner);
    (fees0, fees1) = IFeeCollectNfpm(nfpm).collect(params);
    vm.revertToState(snapshot);
  }
}
