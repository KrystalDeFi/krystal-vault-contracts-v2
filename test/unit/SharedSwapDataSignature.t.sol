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

/// @dev Minimal EIP-1271 wallet: approves exactly one digest. Models a multisig/smart-wallet
///      backend signer, which SignatureChecker.isValidSignatureNow supports alongside EOAs.
contract SharedSwapDataSignature1271Signer {
  bytes32 internal approvedDigest;

  function approveDigest(bytes32 digest) external {
    approvedDigest = digest;
  }

  function isValidSignature(bytes32 digest, bytes memory) external view returns (bytes4) {
    return digest == approvedDigest ? bytes4(0x1626ba7e) : bytes4(0);
  }
}

contract SharedSwapDataSignatureTest is Test {
  uint256 internal constant SIGNER_PK = 0xA11CE;

  /// @dev Storage (not a stack local): with via-ir the optimizer rematerializes CHAINID at the use
  ///      site, so a cached `uint256 local = block.chainid` silently reads the post-vm.chainId value.
  uint256 internal savedChainId;

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

  /// @dev A malformed envelope (here: the trailing `signature` field missing entirely) must revert in
  ///      `decode` rather than mis-assign fields. Pins the 6-field abi.decode shape as a regression guard
  ///      for anyone "simplifying" the envelope ABI without a migration.
  function test_verify_revertsOnTruncatedEnvelope() public {
    SharedSwapDataSignatureHarness harness = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    // Five fields instead of six — abi.decode must revert, not read garbage.
    bytes memory truncated =
      abi.encode(hex"1234", address(0xA), block.timestamp + 1 hours, signer, bytes32("nonce"));

    vm.expectRevert();
    harness.verify(
      ISharedConfigManager(address(config)), address(0xA), address(0xB), address(0xC), address(0xD), 1 ether, 0, truncated
    );
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

  /// @dev The digest embeds block.chainid (SharedSwapDataSignature.hash line 1: `block.chainid`), so the
  ///      same tuple must produce a DIFFERENT digest on a different chain — the binding that makes
  ///      cross-chain signature replay impossible.
  function test_hash_bindsChainId() public {
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

    savedChainId = block.chainid;
    vm.chainId(savedChainId + 1);
    bytes32 otherChainDigest = harness.hash(
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
    vm.chainId(savedChainId);

    assertNotEq(baseDigest, otherChainDigest, "digest must differ across chain ids");
  }

  /// @dev End-to-end cross-chain replay: an envelope signed against chain A's digest must NOT verify on
  ///      chain B. The envelope ABI carries no explicit chain field — the chain id only lives inside the
  ///      signed digest — so on chain B `verify` reconstructs a different digest and the signature check
  ///      fails with InvalidSwapDataSignature.
  function test_verify_rejectsCrossChainReplay() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    address expectedVault = address(0xA);
    address swapRouter = address(0xB);

    // Signed against the CURRENT chain id.
    bytes memory signedSwapData = _signSwapData(
      caller, expectedVault, signer, swapRouter, address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      block.timestamp + 1 hours, bytes32("cross-chain-nonce")
    );

    // Replayed on a different chain: digest reconstruction diverges, signature no longer matches.
    savedChainId = block.chainid;
    vm.chainId(savedChainId + 1);
    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );
    vm.chainId(savedChainId);

    // Back on the home chain the very same envelope verifies — proving the only blocker was the chain id.
    bytes memory decoded = caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );
    assertEq(decoded, hex"1234", "same envelope verifies on the chain it was signed for");
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

  /// @dev Whitelisted signers may be smart-contract wallets: `SignatureChecker.isValidSignatureNow`
  ///      falls back to EIP-1271 for contract signers, so a multisig backend signer must verify the
  ///      same way an EOA does — and a digest the wallet has NOT approved must be rejected.
  function test_verify_supportsEip1271ContractSigner() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    SharedSwapDataSignature1271Signer wallet = new SharedSwapDataSignature1271Signer();
    config.setSigner(address(wallet), true);

    address expectedVault = address(0xA);
    address swapRouter = address(0xB);
    bytes memory rawSwapData = hex"1234";
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 nonce = bytes32("eip1271-nonce");

    bytes32 digest = caller.hash(
      expectedVault, address(wallet), swapRouter, address(0xC), address(0xD), 1 ether, 0.9 ether, rawSwapData,
      deadline, nonce
    );
    wallet.approveDigest(digest);

    // EIP-1271 wallets validate by digest; the envelope's signature bytes are opaque to the wallet.
    bytes memory signedSwapData =
      abi.encode(rawSwapData, expectedVault, deadline, address(wallet), nonce, bytes(hex"00"));
    bytes memory decoded = caller.verify(
      ISharedConfigManager(address(config)), expectedVault, swapRouter, address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );
    assertEq(decoded, rawSwapData, "contract-wallet signer verifies via EIP-1271");
  }

  function test_verify_rejectsEip1271SignerThatDoesNotApproveDigest() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    SharedSwapDataSignature1271Signer wallet = new SharedSwapDataSignature1271Signer();
    config.setSigner(address(wallet), true);

    // Wallet never approves this digest — verification must fail even though the signer is whitelisted.
    bytes memory signedSwapData = abi.encode(
      bytes(hex"1234"), address(0xA), block.timestamp + 1 hours, address(wallet), bytes32("unapproved"),
      bytes(hex"00")
    );
    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    caller.verify(
      ISharedConfigManager(address(config)), address(0xA), address(0xB), address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );
  }

  /// @dev The signer whitelist (SharedSwapDataSignature.verify: `configManager.isWhitelistedSigner`)
  ///      is the authorization root for operator swaps: a perfectly valid signature from a
  ///      NON-whitelisted key must be rejected — and with InvalidSwapDataSignature, before any
  ///      digest computation or replay-state write.
  function test_verify_rejectsUnwhitelistedSigner() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    // signer deliberately NOT whitelisted

    bytes memory signedSwapData = _signSwapData(
      caller, address(0xA), signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      block.timestamp + 1 hours, bytes32("unwhitelisted-signer")
    );

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    caller.verify(
      ISharedConfigManager(address(config)), address(0xA), address(0xB), address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );

    // Whitelisting the signer afterwards makes the very same envelope verify — the only blocker
    // was the whitelist, not the signature itself.
    config.setSigner(signer, true);
    bytes memory decoded = caller.verify(
      ISharedConfigManager(address(config)), address(0xA), address(0xB), address(0xC), address(0xD), 1 ether,
      0.9 ether, signedSwapData
    );
    assertEq(decoded, hex"1234");
  }

  /// @dev Verify-level cross-VAULT replay (complements the hash-level binding test): an envelope
  ///      signed for vault A presented by vault B fails the `envelope.vault == expectedVault` check
  ///      (SharedSwapDataSignature.verify line 1) — before the deadline, whitelist, and signature
  ///      checks ever run.
  function test_verify_rejectsEnvelopeVaultMismatch() public {
    SharedSwapDataSignatureHarness caller = new SharedSwapDataSignatureHarness();
    SharedSwapDataSignatureConfigHarness config = new SharedSwapDataSignatureConfigHarness();
    address signer = vm.addr(SIGNER_PK);
    config.setSigner(signer, true);

    address vaultA = address(0xA);
    address vaultB = address(0xB0B);

    bytes memory signedForVaultA = _signSwapData(
      caller, vaultA, signer, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether, hex"1234",
      block.timestamp + 1 hours, bytes32("cross-vault-nonce")
    );

    vm.expectRevert(ISharedCommon.InvalidSwapDataSignature.selector);
    caller.verify(
      ISharedConfigManager(address(config)), vaultB, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether,
      signedForVaultA
    );

    // Sanity: the same envelope verifies for the vault it was actually signed for.
    bytes memory decoded = caller.verify(
      ISharedConfigManager(address(config)), vaultA, address(0xB), address(0xC), address(0xD), 1 ether, 0.9 ether,
      signedForVaultA
    );
    assertEq(decoded, hex"1234");
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
