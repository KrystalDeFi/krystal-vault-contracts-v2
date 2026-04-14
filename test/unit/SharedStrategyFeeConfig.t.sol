// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { SharedStrategyFeeConfig } from "../../contracts/shared-vault/libraries/SharedStrategyFeeConfig.sol";

contract SharedStrategyFeeConfigHarness {
  function platformFeeX64(ISharedConfigManager cm, uint16 o) external view returns (uint64) {
    return SharedStrategyFeeConfig.platformFeeX64(cm, o);
  }
}

/// @notice Fee sentinel semantics for V3-style strategy payloads (`SharedStrategyFeeConfig`).
contract SharedStrategyFeeConfigTest is Test {
  SharedConfigManager internal cm;
  SharedStrategyFeeConfigHarness internal h;

  function setUp() public {
    cm = new SharedConfigManager();
    cm.initialize(address(this), new address[](0), new address[](0), address(0xABC));
    cm.setPlatformFeeBasisPoint(100);
    h = new SharedStrategyFeeConfigHarness();
  }

  function test_platformFee_typeUint16Max_forcesZero() public view {
    assertEq(h.platformFeeX64(cm, type(uint16).max), 0);
  }

  function test_platformFee_zero_usesConfig_nonZero() public view {
    assertGt(h.platformFeeX64(cm, 0), 0);
  }
}
