// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";

contract SharedSwapDataSignatureSlotHarness {
  function storageSlot() external pure returns (bytes32) {
    return SharedSwapDataSignature.STORAGE_SLOT;
  }
}

contract SharedSwapDataSignatureTest is Test {
  function test_storageSlot_matchesDocumentedNamespaceHash() public {
    bytes32 expected = keccak256("krystal.shared-vault.swap-data-signature.storage");
    assertEq(new SharedSwapDataSignatureSlotHarness().storageSlot(), expected);
  }
}
