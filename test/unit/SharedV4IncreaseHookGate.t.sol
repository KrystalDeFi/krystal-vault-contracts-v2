// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedV4StrategyLib.sol";
import { ISharedV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PositionInfo, PositionInfoLibrary } from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

/// @dev POSM mock covering exactly the external calls the swapAndIncrease / swapAndMint paths make
///      BEFORE `modifyLiquidities`. The first function invoked AFTER the no-liquidity-hook gate
///      (`positionInfo` on the increase path, `poolManager` on the mint path) reverts with the
///      "past-gate" sentinel, so a test asserting that revert proves the gate was reached AND passed
///      without having to mock the full Permit2/modifyLiquidities machinery.
contract MockV4HookGatePosm {
  address internal owner_;
  address internal token0_;
  address internal token1_;
  address internal hooks_;

  constructor(address owner, address token0, address token1) {
    owner_ = owner;
    token0_ = token0;
    token1_ = token1;
  }

  function setHooks(address hooks) external {
    hooks_ = hooks;
  }

  function ownerOf(uint256) external view returns (address) {
    return owner_;
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory key, PositionInfo info) {
    key.currency0 = Currency.wrap(token0_);
    key.currency1 = Currency.wrap(token1_);
    key.fee = 500;
    key.tickSpacing = 60;
    key.hooks = IHooks(hooks_);
    info = PositionInfoLibrary.initialize(key, -60, 60);
  }

  /// @dev Sentinel: first external call after the gate on the increase path.
  function positionInfo(uint256) external pure returns (PositionInfo) {
    revert("past-gate");
  }

  /// @dev Sentinel: first external call after the gate on the mint path.
  function poolManager() external pure returns (IPoolManager) {
    revert("past-gate");
  }
}

/// @dev Delegatecall context for the external library functions: inside the lib, `address(this)` is
///      this harness, which implements the minimal ISharedVault surface the gated paths consult
///      (`isVaultToken`, `weth`). No swaps and no gas fee are encoded, so `configManager` is never
///      read on these paths.
contract V4HookGateHarness {
  mapping(address => bool) internal vaultTokens;

  function setVaultToken(address token) external {
    vaultTokens[token] = true;
  }

  function isVaultToken(address token) external view returns (bool) {
    return vaultTokens[token];
  }

  function weth() external pure returns (address) {
    return address(0xBEEF);
  }

  function swapAndIncrease(address posm, uint256 tokenId, bytes memory params) external {
    SharedV4StrategyLib.swapAndIncreaseCalldata(address(0xDEAD), posm, tokenId, params);
  }

  function swapAndMint(address posm, bytes memory params) external {
    SharedV4StrategyLib.swapAndMintCalldata(address(0xDEAD), posm, params);
  }
}

/// @notice Wiring tests for the no-liquidity-hook auto-gate at the two V4 value-inflow chokepoints:
///         `_increaseV4WithAmounts` (reached by swapAndIncrease and COMPOUND, which only require the
///         NFT to be vault-OWNED — not vault-TRACKED — so a hooked-pool position planted on the
///         vault must be refused before vault funds reach its add-liquidity hook) and
///         `_mintV4WithAmounts` (pre-existing gate, pinned here at the wiring level). The guard
///         function itself is unit-tested in SharedLiquidityHookGate.t.sol.
contract SharedV4IncreaseHookGateTest is Test {
  // Uniswap v4 hook-address permission flags (v4-core Hooks).
  uint160 internal constant V4_BEFORE_ADD_FLAG = uint160(1) << 11;
  uint160 internal constant V4_AFTER_REMOVE_FLAG = uint160(1) << 8;
  uint160 internal constant V4_BEFORE_SWAP_FLAG = uint160(1) << 7;

  address internal token0 = address(0xA0A1);
  address internal token1 = address(0xB0B2);
  V4HookGateHarness internal harness;
  MockV4HookGatePosm internal posm;

  function setUp() public {
    harness = new V4HookGateHarness();
    harness.setVaultToken(token0);
    harness.setVaultToken(token1);
    posm = new MockV4HookGatePosm(address(harness), token0, token1);
  }

  function _increaseCalldata() internal view returns (bytes memory) {
    ISharedV4Utils.SwapAndIncreaseParams memory p;
    p.posm = address(posm);
    p.tokenId = 1;
    p.increaseParams = ISharedV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = new ISharedV4Utils.InputTokenParams[](1);
    p.inputTokens[0] = ISharedV4Utils.InputTokenParams({ token: Currency.wrap(token0), amount: 1e18 });
    p.sweepTokens = new Currency[](0);
    return abi.encodeCall(ISharedV4Utils.swapAndIncrease, (p));
  }

  function _mintCalldata(address hooks) internal view returns (bytes memory) {
    ISharedV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey =
      PoolKey({ currency0: Currency.wrap(token0), currency1: Currency.wrap(token1), fee: 500, tickSpacing: 60, hooks: IHooks(hooks) });
    p.mintParams =
      ISharedV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedV4Utils.SwapParams[](0);
    p.inputTokens = new ISharedV4Utils.InputTokenParams[](1);
    p.inputTokens[0] = ISharedV4Utils.InputTokenParams({ token: Currency.wrap(token0), amount: 1e18 });
    p.sweepTokens = new Currency[](0);
    return abi.encodeCall(ISharedV4Utils.swapAndMint, (p));
  }

  function test_v4_swapAndIncrease_rejectsLiquidityHookPool() public {
    posm.setHooks(address(V4_BEFORE_ADD_FLAG));
    bytes memory data = _increaseCalldata();
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.swapAndIncrease(address(posm), 1, data);
  }

  function test_v4_swapAndIncrease_swapOnlyHook_passesGate() public {
    posm.setHooks(address(V4_BEFORE_SWAP_FLAG));
    bytes memory data = _increaseCalldata();
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndIncrease(address(posm), 1, data);
  }

  function test_v4_swapAndIncrease_hooklessPool_passesGate() public {
    bytes memory data = _increaseCalldata();
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndIncrease(address(posm), 1, data);
  }

  /// @notice Pins the pre-existing mint-path gate at the wiring level (poolKey here is
  ///         caller-supplied, unlike the increase path where it is read from the POSM).
  function test_v4_swapAndMint_rejectsLiquidityHookPool() public {
    bytes memory data = _mintCalldata(address(V4_AFTER_REMOVE_FLAG));
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.swapAndMint(address(posm), data);
  }

  function test_v4_swapAndMint_swapOnlyHook_passesGate() public {
    bytes memory data = _mintCalldata(address(V4_BEFORE_SWAP_FLAG));
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndMint(address(posm), data);
  }
}
