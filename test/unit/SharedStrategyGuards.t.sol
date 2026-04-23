// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedStrategyGuards } from "../../contracts/shared-vault/libraries/SharedStrategyGuards.sol";

/// @notice Thin harness — `SharedStrategyGuards` only exposes `internal` library functions.
contract SharedStrategyGuardsHarness {
  function requireWhitelistedNfpm(ISharedConfigManager cm, address nfpm) external view {
    SharedStrategyGuards.requireWhitelistedNfpm(cm, nfpm);
  }
}

/// @notice Unit tests for NFPM whitelist checks used by shared strategies.
contract SharedStrategyGuardsTest is Test {
  SharedConfigManager internal cm;
  SharedStrategyGuardsHarness internal h;

  address internal listedNfpm = address(0x1001);
  address internal other = address(0x3003);

  function setUp() public {
    cm = new SharedConfigManager();
    address[] memory nfpms = new address[](1);
    nfpms[0] = listedNfpm;
    cm.initialize(address(this), new address[](0), new address[](0), address(0xABC), 0, nfpms, new address[](0));
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
}
