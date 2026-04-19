// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { SharedStrategyBeacon } from "../../contracts/shared-vault/strategies/SharedStrategyBeacon.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";

contract SharedStrategyBeaconTest is TestCommon {
  SharedStrategyBeacon public beacon;

  address public constant OWNER = address(0x1);
  address public constant NON_OWNER = address(0x2);
  address public constant IMPL_V1 = address(0x100);
  address public constant IMPL_V2 = address(0x200);

  function setUp() public {
    beacon = new SharedStrategyBeacon(IMPL_V1, OWNER);
  }

  // ========== Constructor ==========

  function test_constructor_setsImplementation() public view {
    assertEq(beacon.implementation(), IMPL_V1);
  }

  function test_constructor_setsOwner() public view {
    assertEq(beacon.owner(), OWNER);
  }

  function test_constructor_revertsOnZeroImplementation() public {
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    new SharedStrategyBeacon(address(0), OWNER);
  }

  // ========== setImplementation ==========

  function test_setImplementation_updatesAddress() public {
    vm.prank(OWNER);
    beacon.setImplementation(IMPL_V2);

    assertEq(beacon.implementation(), IMPL_V2);
  }

  function test_setImplementation_emitsEvent() public {
    vm.prank(OWNER);
    vm.expectEmit(true, true, false, false, address(beacon));
    emit SharedStrategyBeacon.ImplementationUpgraded(IMPL_V1, IMPL_V2);
    beacon.setImplementation(IMPL_V2);
  }

  function test_setImplementation_revertsOnZeroAddress() public {
    vm.prank(OWNER);
    vm.expectRevert(ISharedCommon.ZeroAddress.selector);
    beacon.setImplementation(address(0));
  }

  function test_setImplementation_revertsForNonOwner() public {
    vm.prank(NON_OWNER);
    vm.expectRevert();
    beacon.setImplementation(IMPL_V2);
  }

  // ========== Ownership ==========

  function test_transferOwnership_changesOwner() public {
    address newOwner = address(0x3);

    vm.prank(OWNER);
    beacon.transferOwnership(newOwner);

    assertEq(beacon.owner(), newOwner);
  }

  function test_transferOwnership_newOwnerCanUpgrade() public {
    address newOwner = address(0x3);

    vm.prank(OWNER);
    beacon.transferOwnership(newOwner);

    vm.prank(newOwner);
    beacon.setImplementation(IMPL_V2);

    assertEq(beacon.implementation(), IMPL_V2);
  }

  function test_transferOwnership_oldOwnerCannotUpgrade() public {
    address newOwner = address(0x3);

    vm.prank(OWNER);
    beacon.transferOwnership(newOwner);

    vm.prank(OWNER);
    vm.expectRevert();
    beacon.setImplementation(IMPL_V2);
  }
}
