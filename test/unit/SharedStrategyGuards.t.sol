// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedStrategyGuards } from "../../contracts/shared-vault/libraries/SharedStrategyGuards.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

/// @notice Thin harness — `SharedStrategyGuards` only exposes `internal` library functions.
contract SharedStrategyGuardsHarness {
  function requireWhitelistedNfpm(ISharedConfigManager cm, address nfpm) external view {
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);
  }

  function requireWhitelistedOxSwapData(ISharedConfigManager cm, bytes memory swapData) external view {
    SharedStrategyGuards.requireWhitelistedOxSwapData(cm, swapData);
  }

  function requireWhitelistedV3SwapRoutersSwapAndMint(
    ISharedConfigManager cm,
    IV3Utils.SwapAndMintParams memory p
  ) external view {
    SharedStrategyGuards.requireWhitelistedV3SwapRoutersSwapAndMint(cm, p);
  }

  function requireWhitelistedV3SwapRoutersSwapAndIncrease(
    ISharedConfigManager cm,
    IV3Utils.SwapAndIncreaseLiquidityParams memory p
  ) external view {
    SharedStrategyGuards.requireWhitelistedV3SwapRoutersSwapAndIncrease(cm, p);
  }

  function requireWhitelistedV3SwapRoutersInstructions(
    ISharedConfigManager cm,
    IV3Utils.Instructions memory ins
  ) external view {
    SharedStrategyGuards.requireWhitelistedV3SwapRoutersInstructions(cm, ins);
  }
}

/// @notice Unit tests for NFPM and Ox-style swap-router whitelist checks used by shared strategies.
contract SharedStrategyGuardsTest is Test {
  SharedConfigManager internal cm;
  SharedStrategyGuardsHarness internal h;

  address internal listedNfpm = address(0x1001);
  address internal listedRouter = address(0x2002);
  address internal other = address(0x3003);

  function setUp() public {
    cm = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = listedNfpm;
    address[] memory routers = new address[](1);
    routers[0] = listedRouter;
    cm.initialize(address(this), new address[](0), new address[](0), address(0xABC), nfpms, routers);
    h = new SharedStrategyGuardsHarness();
  }

  function test_requireWhitelistedNfpm_revertsOnZeroAddress() public {
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    h.requireWhitelistedNfpm(cm, address(0));
  }

  function test_requireWhitelistedNfpm_revertsWhenNotWhitelisted() public {
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidNfpm.selector, other));
    h.requireWhitelistedNfpm(cm, other);
  }

  function test_requireWhitelistedNfpm_succeedsWhenWhitelisted() public view {
    h.requireWhitelistedNfpm(cm, listedNfpm);
  }

  function test_requireWhitelistedOxSwapData_noOpWhenEmpty() public view {
    h.requireWhitelistedOxSwapData(cm, "");
  }

  function test_requireWhitelistedOxSwapData_revertsWhenRouterNotWhitelisted() public {
    bytes memory swapData = abi.encode(other, hex"");
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, other));
    h.requireWhitelistedOxSwapData(cm, swapData);
  }

  function test_requireWhitelistedOxSwapData_succeedsWhenRouterWhitelisted() public view {
    bytes memory swapData = abi.encode(listedRouter, hex"abcd");
    h.requireWhitelistedOxSwapData(cm, swapData);
  }

  function test_requireWhitelistedV3SwapRoutersSwapAndMint_succeedsWithEmptySwapData() public view {
    IV3Utils.SwapAndMintParams memory p = _emptySwapAndMintParams();
    h.requireWhitelistedV3SwapRoutersSwapAndMint(cm, p);
  }

  function test_requireWhitelistedV3SwapRoutersSwapAndMint_revertsOnBadRouterInSwapData0() public {
    IV3Utils.SwapAndMintParams memory p = _emptySwapAndMintParams();
    p.swapData0 = abi.encode(other, hex"");
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, other));
    h.requireWhitelistedV3SwapRoutersSwapAndMint(cm, p);
  }

  function test_requireWhitelistedV3SwapRoutersSwapAndMint_revertsOnBadRouterInSwapData1() public {
    IV3Utils.SwapAndMintParams memory p = _emptySwapAndMintParams();
    p.swapData1 = abi.encode(other, hex"");
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, other));
    h.requireWhitelistedV3SwapRoutersSwapAndMint(cm, p);
  }

  function test_requireWhitelistedV3SwapRoutersSwapAndIncrease_succeedsWithEmptySwapData() public view {
    IV3Utils.SwapAndIncreaseLiquidityParams memory p = _emptySwapAndIncreaseParams();
    h.requireWhitelistedV3SwapRoutersSwapAndIncrease(cm, p);
  }

  function test_requireWhitelistedV3SwapRoutersSwapAndIncrease_revertsOnBadRouter() public {
    IV3Utils.SwapAndIncreaseLiquidityParams memory p = _emptySwapAndIncreaseParams();
    p.swapData0 = abi.encode(other, hex"");
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, other));
    h.requireWhitelistedV3SwapRoutersSwapAndIncrease(cm, p);
  }

  function test_requireWhitelistedV3SwapRoutersInstructions_succeedsWithEmptySwapData() public view {
    IV3Utils.Instructions memory ins = _emptyInstructions();
    h.requireWhitelistedV3SwapRoutersInstructions(cm, ins);
  }

  function test_requireWhitelistedV3SwapRoutersInstructions_revertsOnBadRouter() public {
    IV3Utils.Instructions memory ins = _emptyInstructions();
    ins.swapData1 = abi.encode(other, hex"");
    vm.expectRevert(abi.encodeWithSelector(ISharedCommon.InvalidSwapRouter.selector, other));
    h.requireWhitelistedV3SwapRoutersInstructions(cm, ins);
  }

  function _emptySwapAndMintParams() private pure returns (IV3Utils.SwapAndMintParams memory p) {
    p.swapData0 = "";
    p.swapData1 = "";
  }

  function _emptySwapAndIncreaseParams() private pure returns (IV3Utils.SwapAndIncreaseLiquidityParams memory p) {
    p.swapData0 = "";
    p.swapData1 = "";
  }

  function _emptyInstructions() private pure returns (IV3Utils.Instructions memory ins) {
    ins.swapData0 = "";
    ins.swapData1 = "";
  }
}
