// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";

contract SharedSwapDataSignatureHarness {
  function storageSlot() external pure returns (bytes32) {
    return SharedSwapDataSignature.STORAGE_SLOT;
  }

  function hash(
    address vault,
    address signer,
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData,
    uint256 deadline,
    bytes32 nonce
  ) external view returns (bytes32) {
    return SharedSwapDataSignature.hash(
      vault, signer, swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, swapData, deadline, nonce
    );
  }

  function verify(
    ISharedConfigManager configManager,
    address expectedVault,
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory signedSwapData
  ) external returns (bytes memory swapData) {
    return SharedSwapDataSignature.verify(
      configManager, expectedVault, swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, signedSwapData
    );
  }
}

contract SharedSwapDataSignatureConfigHarness {
  mapping(address => bool) public isWhitelistedSigner;

  function setSigner(address signer, bool isWhitelisted) external {
    isWhitelistedSigner[signer] = isWhitelisted;
  }
}

contract SharedSwapDataSignatureTest is Test {
  uint256 internal constant SIGNER_PK = 0xA11CE;

  function test_storageSlot_matchesDocumentedNamespaceHash() public {
    bytes32 expected = keccak256("krystal.shared-vault.swap-data-signature.storage");
    assertEq(new SharedSwapDataSignatureHarness().storageSlot(), expected);
  }

  function test_hash_bindsVaultAndDeadline() public {
    SharedSwapDataSignatureHarness harness = new SharedSwapDataSignatureHarness();

    bytes32 baseDigest = harness.hash(
      address(0xA),
      vm.addr(SIGNER_PK),
      address(0xB),
      address(0xC),
      address(0xD),
      1 ether,
      0.9 ether,
      hex"1234",
      block.timestamp + 1 hours,
      bytes32("nonce")
    );

    bytes32 otherVaultDigest = harness.hash(
      address(0xE),
      vm.addr(SIGNER_PK),
      address(0xB),
      address(0xC),
      address(0xD),
      1 ether,
      0.9 ether,
      hex"1234",
      block.timestamp + 1 hours,
      bytes32("nonce")
    );
    bytes32 otherDeadlineDigest = harness.hash(
      address(0xA),
      vm.addr(SIGNER_PK),
      address(0xB),
      address(0xC),
      address(0xD),
      1 ether,
      0.9 ether,
      hex"1234",
      block.timestamp + 2 hours,
      bytes32("nonce")
    );

    assertNotEq(baseDigest, otherVaultDigest);
    assertNotEq(baseDigest, otherDeadlineDigest);
  }

  function test_verify_consumesDigestInCallerStorage() public {
    SharedSwapDataSignatureHarness callerA = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureHarness callerB = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    address expectedVault = address(0xA);
    address swapRouter = address(0xB);
    address tokenIn = address(0xC);
    address tokenOut = address(0xD);
    uint256 amountIn = 1 ether;
    uint256 amountOutMin = 0.9 ether;
    bytes memory rawSwapData = hex"1234";
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 nonce = bytes32("shared-nonce");

    bytes memory signedSwapData = _signSwapData(
      callerA,
      expectedVault,
      signer,
      swapRouter,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      nonce
    );

    bytes memory decodedSwapData = callerA.verify(
      ISharedConfigManager(address(config)),
      expectedVault,
      swapRouter,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      signedSwapData
    );
    assertEq(decodedSwapData, rawSwapData);

    vm.expectRevert(ISharedCommon.SwapDataSignatureAlreadyUsed.selector);
    callerA.verify(
      ISharedConfigManager(address(config)),
      expectedVault,
      swapRouter,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      signedSwapData
    );

    decodedSwapData = callerB.verify(
      ISharedConfigManager(address(config)),
      expectedVault,
      swapRouter,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      signedSwapData
    );
    assertEq(decodedSwapData, rawSwapData);
  }

  /// @dev Pins the order of the replay check vs signature verification (SharedSwapDataSignature.sol:
  ///      "Check replay state before signature verification"). Once a digest is consumed, re-submitting
  ///      the same envelope with CORRUPTED signature bytes must surface SwapDataSignatureAlreadyUsed —
  ///      not InvalidSwapDataSignature — proving the consumed-digest check runs first. (The digest does
  ///      not cover the signature bytes, so the corrupted envelope still maps to the consumed digest.)
  function test_verify_consumedDigest_surfacesBeforeInvalidSignature() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    address expectedVault = address(0xA);
    address swapRouter = address(0xB);
    bytes memory rawSwapData = hex"1234";
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 nonce = bytes32("priority-nonce");

    bytes memory signedSwapData = _signSwapData(
      caller, expectedVault, signer, swapRouter, address(0xC), address(0xD), 1 ether, 0.9 ether, rawSwapData,
      deadline, nonce
    );
    caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );

    // Same envelope fields, garbage signature: digest is identical and already consumed.
    bytes memory corrupted = abi.encode(rawSwapData, expectedVault, deadline, signer, nonce, bytes(hex"deadbeef"));
    vm.expectRevert(ISharedCommon.SwapDataSignatureAlreadyUsed.selector);
    caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, corrupted
    );
  }

  /// @dev `deadline >= block.timestamp` is inclusive: a signature expiring exactly now must still verify,
  ///      and one second past must revert SwapDataSignatureExpired.
  function test_verify_deadlineBoundary() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    address expectedVault = address(0xA);
    address swapRouter = address(0xB);

    bytes memory atNow = _signSwapData(
      caller, expectedVault, signer, swapRouter, address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      block.timestamp, bytes32("deadline-now")
    );
    bytes memory decoded = caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, atNow
    );
    assertEq(decoded, hex"1234", "deadline == block.timestamp verifies");

    bytes memory expired = _signSwapData(
      caller, expectedVault, signer, swapRouter, address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      block.timestamp - 1, bytes32("deadline-past")
    );
    vm.expectRevert(ISharedCommon.SwapDataSignatureExpired.selector);
    caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, expired
    );
  }

  /// @dev Completes the digest-binding coverage of test_hash_bindsVaultAndDeadline: every remaining
  ///      field of the signed tuple — router, tokenIn, tokenOut, amountIn, amountOutMin, swapData,
  ///      nonce, signer — must change the digest, or a signature could be replayed across that field.
  function test_hash_bindsAllRemainingFields() public {
    SharedSwapDataSignatureHarness harness = new SharedSwapDataSignatureHarness();
    address signer = vm.addr(SIGNER_PK);
    uint256 deadline = block.timestamp + 1 hours;

    bytes32 base =
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce"));

    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xBB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce")),
      "router not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xCC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce")),
      "tokenIn not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xDD), 1 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce")),
      "tokenOut not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xD), 2 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce")),
      "amountIn not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.8 ether, hex"1234",
      deadline, bytes32("nonce")),
      "amountOutMin not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"125678",
      deadline, bytes32("nonce")),
      "swapData not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      deadline, bytes32("nonce2")),
      "nonce not bound"
    );
    assertNotEq(
      base,
      harness.hash(address(0xA), address(0xE), address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether,
      hex"1234", deadline, bytes32("nonce")),
      "signer not bound"
    );
  }

  function _signSwapData(
    SharedSwapDataSignatureHarness harness,
    address vault,
    address signer,
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData,
    uint256 deadline,
    bytes32 nonce
  ) internal view returns (bytes memory) {
    bytes32 digest = harness.hash(
      vault, signer, swapRouter, tokenIn, tokenOut, amountIn, amountOutMin, rawSwapData, deadline, nonce
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
    return abi.encode(rawSwapData, vault, deadline, signer, nonce, abi.encodePacked(r, s, v));
  }
}
