// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SharedConfigManagerTest is TestCommon {
  SharedConfigManager public configManager;

  address public constant OWNER = address(0x1);
  address public constant NON_OWNER = address(0x2);
  address public constant FEE_RECIPIENT = address(0x3);

  address public constant TARGET_A = address(0x100);
  address public constant TARGET_B = address(0x101);
  address public constant CALLER_A = address(0x200);
  address public constant NFPM_A = address(0x300);
  address public constant ROUTER_A = address(0x400);

  function setUp() public {
    configManager = new SharedConfigManager();

    address[] memory targets = new address[](1);
    targets[0] = TARGET_A;
    address[] memory callers = new address[](1);
    callers[0] = CALLER_A;
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM_A;
    address[] memory routers = new address[](1);
    routers[0] = ROUTER_A;

    configManager.initialize(OWNER, targets, callers, FEE_RECIPIENT, nfpms, routers);
  }

  // ========== initialize ==========

  function test_initialize_setsOwner() public view {
    assertEq(configManager.owner(), OWNER);
  }

  function test_initialize_setsFeeRecipient() public view {
    assertEq(configManager.feeRecipient(), FEE_RECIPIENT);
  }

  function test_initialize_setsWhitelistTargets() public view {
    assertTrue(configManager.isWhitelistedTarget(TARGET_A));
    assertFalse(configManager.isWhitelistedTarget(TARGET_B));
  }

  function test_initialize_setsWhitelistCallers() public view {
    assertTrue(configManager.isWhitelistedCaller(CALLER_A));
    assertFalse(configManager.isWhitelistedCaller(NON_OWNER));
  }

  function test_initialize_setsWhitelistNfpms() public view {
    assertTrue(configManager.isWhitelistedNfpm(NFPM_A));
    assertFalse(configManager.isWhitelistedNfpm(NON_OWNER));
  }

  function test_initialize_setsWhitelistSwapRouters() public view {
    assertTrue(configManager.isWhitelistedSwapRouter(ROUTER_A));
    assertFalse(configManager.isWhitelistedSwapRouter(NON_OWNER));
  }

  function test_initialize_defaultPlatformFeeBpsIsZero() public view {
    assertEq(configManager.platformFeeBasisPoint(), 0);
  }

  function test_initialize_defaultVaultPausedIsFalse() public view {
    assertFalse(configManager.isVaultPaused());
  }

  function test_initialize_emitsWhitelistEvents() public {
    SharedConfigManager fresh = new SharedConfigManager();

    address[] memory targets = new address[](1);
    targets[0] = TARGET_B;
    address[] memory callers = new address[](1);
    callers[0] = CALLER_A;
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM_A;
    address[] memory routers = new address[](1);
    routers[0] = ROUTER_A;

    vm.expectEmit(false, false, false, true, address(fresh));
    emit ISharedConfigManager.WhitelistTargetsUpdated(targets, true);

    fresh.initialize(OWNER, targets, callers, FEE_RECIPIENT, nfpms, routers);
  }

  function test_initialize_withEmptyArraysDoesNotEmit() public {
    // Should not revert when all arrays are empty
    SharedConfigManager fresh = new SharedConfigManager();
    fresh.initialize(OWNER, new address[](0), new address[](0), FEE_RECIPIENT, new address[](0), new address[](0));

    assertEq(fresh.owner(), OWNER);
    assertFalse(fresh.isWhitelistedTarget(TARGET_A));
  }

  function test_initialize_revertsIfCalledTwice() public {
    vm.expectRevert();
    configManager.initialize(OWNER, new address[](0), new address[](0), FEE_RECIPIENT, new address[](0), new address[](0));
  }

  // ========== setWhitelistTargets ==========

  function test_setWhitelistTargets_addsAddress() public {
    address[] memory targets = new address[](1);
    targets[0] = TARGET_B;

    vm.prank(OWNER);
    configManager.setWhitelistTargets(targets, true);

    assertTrue(configManager.isWhitelistedTarget(TARGET_B));
  }

  function test_setWhitelistTargets_removesAddress() public {
    address[] memory targets = new address[](1);
    targets[0] = TARGET_A;

    vm.prank(OWNER);
    configManager.setWhitelistTargets(targets, false);

    assertFalse(configManager.isWhitelistedTarget(TARGET_A));
  }

  function test_setWhitelistTargets_multiple() public {
    address[] memory targets = new address[](2);
    targets[0] = TARGET_A;
    targets[1] = TARGET_B;

    vm.prank(OWNER);
    configManager.setWhitelistTargets(targets, true);

    assertTrue(configManager.isWhitelistedTarget(TARGET_A));
    assertTrue(configManager.isWhitelistedTarget(TARGET_B));
  }

  function test_setWhitelistTargets_emitsEvent() public {
    address[] memory targets = new address[](1);
    targets[0] = TARGET_B;

    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.WhitelistTargetsUpdated(targets, true);
    configManager.setWhitelistTargets(targets, true);
  }

  function test_setWhitelistTargets_revertsForNonOwner() public {
    address[] memory targets = new address[](1);
    targets[0] = TARGET_B;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setWhitelistTargets(targets, true);
  }

  // ========== setWhitelistCallers ==========

  function test_setWhitelistCallers_addsAddress() public {
    address[] memory callers = new address[](1);
    callers[0] = NON_OWNER;

    vm.prank(OWNER);
    configManager.setWhitelistCallers(callers, true);

    assertTrue(configManager.isWhitelistedCaller(NON_OWNER));
  }

  function test_setWhitelistCallers_removesAddress() public {
    address[] memory callers = new address[](1);
    callers[0] = CALLER_A;

    vm.prank(OWNER);
    configManager.setWhitelistCallers(callers, false);

    assertFalse(configManager.isWhitelistedCaller(CALLER_A));
  }

  function test_setWhitelistCallers_emitsEvent() public {
    address[] memory callers = new address[](1);
    callers[0] = NON_OWNER;

    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.WhitelistCallersUpdated(callers, true);
    configManager.setWhitelistCallers(callers, true);
  }

  function test_setWhitelistCallers_revertsForNonOwner() public {
    address[] memory callers = new address[](1);
    callers[0] = NON_OWNER;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setWhitelistCallers(callers, true);
  }

  // ========== setWhitelistNfpms ==========

  function test_setWhitelistNfpms_addsAddress() public {
    address newNfpm = address(0x301);
    address[] memory nfpms = new address[](1);
    nfpms[0] = newNfpm;

    vm.prank(OWNER);
    configManager.setWhitelistNfpms(nfpms, true);

    assertTrue(configManager.isWhitelistedNfpm(newNfpm));
  }

  function test_setWhitelistNfpms_removesAddress() public {
    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM_A;

    vm.prank(OWNER);
    configManager.setWhitelistNfpms(nfpms, false);

    assertFalse(configManager.isWhitelistedNfpm(NFPM_A));
  }

  function test_setWhitelistNfpms_emitsEvent() public {
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(0x301);

    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.WhitelistNfpmsUpdated(nfpms, true);
    configManager.setWhitelistNfpms(nfpms, true);
  }

  function test_setWhitelistNfpms_revertsForNonOwner() public {
    address[] memory nfpms = new address[](1);
    nfpms[0] = address(0x999);

    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setWhitelistNfpms(nfpms, true);
  }

  // ========== setWhitelistSwapRouters ==========

  function test_setWhitelistSwapRouters_addsAddress() public {
    address newRouter = address(0x401);
    address[] memory routers = new address[](1);
    routers[0] = newRouter;

    vm.prank(OWNER);
    configManager.setWhitelistSwapRouters(routers, true);

    assertTrue(configManager.isWhitelistedSwapRouter(newRouter));
  }

  function test_setWhitelistSwapRouters_removesAddress() public {
    address[] memory routers = new address[](1);
    routers[0] = ROUTER_A;

    vm.prank(OWNER);
    configManager.setWhitelistSwapRouters(routers, false);

    assertFalse(configManager.isWhitelistedSwapRouter(ROUTER_A));
  }

  function test_setWhitelistSwapRouters_emitsEvent() public {
    address[] memory routers = new address[](1);
    routers[0] = address(0x401);

    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.WhitelistSwapRoutersUpdated(routers, true);
    configManager.setWhitelistSwapRouters(routers, true);
  }

  function test_setWhitelistSwapRouters_revertsForNonOwner() public {
    address[] memory routers = new address[](1);
    routers[0] = address(0x999);

    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setWhitelistSwapRouters(routers, true);
  }

  // ========== setVaultPaused ==========

  function test_setVaultPaused_pauses() public {
    vm.prank(OWNER);
    configManager.setVaultPaused(true);

    assertTrue(configManager.isVaultPaused());
  }

  function test_setVaultPaused_unpauses() public {
    vm.prank(OWNER);
    configManager.setVaultPaused(true);

    vm.prank(OWNER);
    configManager.setVaultPaused(false);

    assertFalse(configManager.isVaultPaused());
  }

  function test_setVaultPaused_emitsEvent() public {
    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.VaultPausedUpdated(true);
    configManager.setVaultPaused(true);
  }

  function test_setVaultPaused_revertsForNonOwner() public {
    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setVaultPaused(true);
  }

  // ========== setFeeRecipient ==========

  function test_setFeeRecipient_updatesAddress() public {
    address newRecipient = address(0x999);

    vm.prank(OWNER);
    configManager.setFeeRecipient(newRecipient);

    assertEq(configManager.feeRecipient(), newRecipient);
  }

  function test_setFeeRecipient_emitsEvent() public {
    address newRecipient = address(0x999);

    vm.prank(OWNER);
    vm.expectEmit(true, true, false, false, address(configManager));
    emit ISharedConfigManager.FeeRecipientUpdated(FEE_RECIPIENT, newRecipient);
    configManager.setFeeRecipient(newRecipient);
  }

  function test_setFeeRecipient_revertsOnZeroAddress() public {
    vm.prank(OWNER);
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    configManager.setFeeRecipient(address(0));
  }

  function test_setFeeRecipient_revertsForNonOwner() public {
    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setFeeRecipient(address(0x999));
  }

  // ========== setPlatformFeeBasisPoint ==========

  function test_setPlatformFeeBasisPoint_setsValue() public {
    vm.prank(OWNER);
    configManager.setPlatformFeeBasisPoint(500);

    assertEq(configManager.platformFeeBasisPoint(), 500);
  }

  function test_setPlatformFeeBasisPoint_allowsMaxValue() public {
    vm.prank(OWNER);
    configManager.setPlatformFeeBasisPoint(10_000);

    assertEq(configManager.platformFeeBasisPoint(), 10_000);
  }

  function test_setPlatformFeeBasisPoint_allowsZero() public {
    vm.prank(OWNER);
    configManager.setPlatformFeeBasisPoint(500);

    vm.prank(OWNER);
    configManager.setPlatformFeeBasisPoint(0);

    assertEq(configManager.platformFeeBasisPoint(), 0);
  }

  function test_setPlatformFeeBasisPoint_revertsAboveMax() public {
    vm.prank(OWNER);
    vm.expectRevert(ISharedCommon.InvalidFeeBasisPoint.selector);
    configManager.setPlatformFeeBasisPoint(10_001);
  }

  function test_setPlatformFeeBasisPoint_revertsForNonOwner() public {
    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setPlatformFeeBasisPoint(500);
  }

  // ========== setMaxPositions ==========

  function test_initialize_defaultMaxPositionsIs20() public view {
    assertEq(configManager.maxPositions(), 20);
  }

  function test_setMaxPositions_updatesValue() public {
    vm.prank(OWNER);
    configManager.setMaxPositions(5);

    assertEq(configManager.maxPositions(), 5);
  }

  function test_setMaxPositions_allowsOne() public {
    vm.prank(OWNER);
    configManager.setMaxPositions(1);

    assertEq(configManager.maxPositions(), 1);
  }

  function test_setMaxPositions_allowsLargeValue() public {
    vm.prank(OWNER);
    configManager.setMaxPositions(type(uint16).max);

    assertEq(configManager.maxPositions(), type(uint16).max);
  }

  function test_setMaxPositions_revertsOnZero() public {
    vm.prank(OWNER);
    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    configManager.setMaxPositions(0);
  }

  function test_setMaxPositions_revertsForNonOwner() public {
    vm.prank(NON_OWNER);
    vm.expectRevert();
    configManager.setMaxPositions(5);
  }

  function test_setMaxPositions_emitsEvent() public {
    vm.prank(OWNER);
    vm.expectEmit(false, false, false, true, address(configManager));
    emit ISharedConfigManager.MaxPositionsUpdated(5);
    configManager.setMaxPositions(5);
  }

  function test_setMaxPositions_canBeUpdatedMultipleTimes() public {
    vm.startPrank(OWNER);
    configManager.setMaxPositions(10);
    assertEq(configManager.maxPositions(), 10);

    configManager.setMaxPositions(3);
    assertEq(configManager.maxPositions(), 3);
    vm.stopPrank();
  }
}
