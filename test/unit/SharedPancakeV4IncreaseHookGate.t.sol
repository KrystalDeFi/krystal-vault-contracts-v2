// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedPancakeV4StrategyLib } from "../../contracts/shared-vault/libraries/SharedPancakeV4StrategyLib.sol";
import { ISharedPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import {
  CLPositionInfo,
  CLPositionInfoLibrary
} from "infinity-periphery/src/pool-cl/libraries/CLPositionInfoLibrary.sol";

/// @dev Sentinel CL pool manager: the first external call AFTER the no-liquidity-hook gate on both
///      the increase path and the mint path is `getSlot0` on `poolKey.poolManager`, so any call
///      reaching this contract proves the gate was reached AND passed.
contract MockPastGateCLPoolManager {
  fallback() external {
    revert("past-gate");
  }
}

/// @dev CL POSM mock covering exactly the external calls the swapAndIncrease / swapAndMint paths
///      make before `modifyLiquidities`: `ownerOf`, `getPoolAndPositionInfo` (also re-read after the
///      gate on the increase path — it must NOT revert) and `clPoolManager` (the F19 pin on the
///      mint path).
contract MockPancakeHookGatePosm {
  address internal owner_;
  address internal token0_;
  address internal token1_;
  address internal manager_;
  bytes32 internal parameters_;

  constructor(address owner, address token0, address token1, address manager) {
    owner_ = owner;
    token0_ = token0;
    token1_ = token1;
    manager_ = manager;
  }

  function setParameters(bytes32 parameters) external {
    parameters_ = parameters;
  }

  function ownerOf(uint256) external view returns (address) {
    return owner_;
  }

  function clPoolManager() external view returns (address) {
    return manager_;
  }

  function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory key, CLPositionInfo info) {
    key.currency0 = Currency.wrap(token0_);
    key.currency1 = Currency.wrap(token1_);
    key.hooks = IHooks(address(0));
    key.poolManager = IPoolManager(manager_);
    key.fee = 500;
    key.parameters = parameters_;
    info = CLPositionInfoLibrary.initialize(key, -60, 60);
  }
}

/// @dev Delegatecall context for the external library functions; implements the minimal
///      ISharedVault surface the gated paths consult (`isVaultToken`, `weth`).
contract PancakeHookGateHarness {
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
    SharedPancakeV4StrategyLib.swapAndIncreaseCalldata(address(0xDEAD), posm, tokenId, params);
  }

  function swapAndMint(address posm, bytes memory params) external {
    SharedPancakeV4StrategyLib.swapAndMintCalldata(address(0xDEAD), posm, params);
  }
}

/// @notice Twin of SharedV4IncreaseHookGate.t.sol for the PancakeSwap Infinity fork: wiring tests
///         for the no-liquidity-hook auto-gate at `_increaseV4WithAmounts` (swapAndIncrease /
///         COMPOUND accept any vault-OWNED tokenId, tracked or not) and at `_mintV4WithAmounts`
///         (pre-existing gate). The guard itself is unit-tested in SharedLiquidityHookGate.t.sol.
contract SharedPancakeV4IncreaseHookGateTest is Test {
  // PancakeSwap Infinity registration bitmap offsets (infinity-core ICLHooks).
  uint8 internal constant CL_BEFORE_ADD_OFFSET = 2;
  uint8 internal constant CL_AFTER_REMOVE_OFFSET = 5;
  uint8 internal constant CL_BEFORE_SWAP_OFFSET = 6;

  address internal token0 = address(0xA0A1);
  address internal token1 = address(0xB0B2);
  PancakeHookGateHarness internal harness;
  MockPancakeHookGatePosm internal posm;
  address internal manager;

  function setUp() public {
    harness = new PancakeHookGateHarness();
    harness.setVaultToken(token0);
    harness.setVaultToken(token1);
    manager = address(new MockPastGateCLPoolManager());
    posm = new MockPancakeHookGatePosm(address(harness), token0, token1, manager);
  }

  function _clParams(uint8 offset) internal pure returns (bytes32) {
    return bytes32(uint256(1) << offset);
  }

  function _increaseCalldata() internal view returns (bytes memory) {
    ISharedPancakeV4Utils.SwapAndIncreaseParams memory p;
    p.posm = address(posm);
    p.tokenId = 1;
    p.increaseParams = ISharedPancakeV4Utils.IncreaseLiquidityParams({ minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.inputTokens = new ISharedPancakeV4Utils.InputTokenParams[](1);
    p.inputTokens[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(token0), amount: 1e18 });
    p.sweepTokens = new Currency[](0);
    return abi.encodeCall(ISharedPancakeV4Utils.swapAndIncrease, (p));
  }

  function _mintCalldata(bytes32 parameters) internal view returns (bytes memory) {
    ISharedPancakeV4Utils.SwapAndMintParams memory p;
    p.posm = address(posm);
    p.poolKey = PoolKey({
      currency0: Currency.wrap(token0),
      currency1: Currency.wrap(token1),
      hooks: IHooks(address(0)),
      poolManager: IPoolManager(manager),
      fee: 500,
      parameters: parameters
    });
    p.mintParams =
      ISharedPancakeV4Utils.MintParams({ tickLower: -60, tickUpper: 60, minLiquidity: 0, hookData: "", deadline: 0 });
    p.swapParams = new ISharedPancakeV4Utils.SwapParams[](0);
    p.inputTokens = new ISharedPancakeV4Utils.InputTokenParams[](1);
    p.inputTokens[0] = ISharedPancakeV4Utils.InputTokenParams({ token: Currency.wrap(token0), amount: 1e18 });
    p.sweepTokens = new Currency[](0);
    return abi.encodeCall(ISharedPancakeV4Utils.swapAndMint, (p));
  }

  function test_pancake_swapAndIncrease_rejectsLiquidityHookPool() public {
    posm.setParameters(_clParams(CL_BEFORE_ADD_OFFSET));
    bytes memory data = _increaseCalldata();
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.swapAndIncrease(address(posm), 1, data);
  }

  function test_pancake_swapAndIncrease_swapOnlyHook_passesGate() public {
    posm.setParameters(_clParams(CL_BEFORE_SWAP_OFFSET));
    bytes memory data = _increaseCalldata();
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndIncrease(address(posm), 1, data);
  }

  function test_pancake_swapAndIncrease_hooklessPool_passesGate() public {
    bytes memory data = _increaseCalldata();
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndIncrease(address(posm), 1, data);
  }

  /// @notice Pins the pre-existing mint-path gate at the wiring level (poolKey here is
  ///         caller-supplied; its poolManager must match the POSM's clPoolManager per F19).
  function test_pancake_swapAndMint_rejectsLiquidityHookPool() public {
    bytes memory data = _mintCalldata(_clParams(CL_AFTER_REMOVE_OFFSET));
    vm.expectRevert(ISharedCommon.UnsupportedLiquidityHook.selector);
    harness.swapAndMint(address(posm), data);
  }

  function test_pancake_swapAndMint_swapOnlyHook_passesGate() public {
    bytes memory data = _mintCalldata(_clParams(CL_BEFORE_SWAP_OFFSET));
    vm.expectRevert(bytes("past-gate"));
    harness.swapAndMint(address(posm), data);
  }
}
