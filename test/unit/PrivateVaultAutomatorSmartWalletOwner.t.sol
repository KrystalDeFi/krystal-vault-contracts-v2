// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

/// @dev Minimal whitelisted target for the multicall body.
contract SmartWalletMockStrategy {
  uint256 public value;

  function setValue(uint256 _value) external {
    value = _value;
  }
}

/// @dev Exposes the automator's EIP-712 digest helper for tests.
contract AutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }

  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @dev Faithful stand-in for a Coinbase Smart Wallet with a single secp256k1 (address) owner.
///      Mirrors the real contract: signature is an ABI-encoded SignatureWrapper, and the inner
///      ECDSA signature is verified over `replaySafeHash(hash)` (a nested EIP-712 wrap bound to
///      this account + chain). Passkey/WebAuthn owners are covered separately in Phase B.
contract MockCoinbaseSmartWalletK1 {
  struct SignatureWrapper {
    uint256 ownerIndex;
    bytes signatureData;
  }

  bytes4 private constant MAGIC = 0x1626ba7e;
  bytes32 private constant MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
  bytes32 private constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  address public immutable owner;

  constructor(address _owner) {
    owner = _owner;
  }

  function _domainSeparator() internal view returns (bytes32) {
    return keccak256(
      abi.encode(DOMAIN_TYPEHASH, keccak256("Coinbase Smart Wallet"), keccak256("1"), block.chainid, address(this))
    );
  }

  /// @notice Same nested-EIP-712 replay-safe wrap the real wallet applies before verifying.
  function replaySafeHash(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(MESSAGE_TYPEHASH, hash))));
  }

  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
    SignatureWrapper memory wrapper = abi.decode(signature, (SignatureWrapper));
    if (wrapper.ownerIndex != 0) return 0xffffffff;
    return ECDSA.recover(replaySafeHash(hash), wrapper.signatureData) == owner ? MAGIC : bytes4(0xffffffff);
  }
}

/// @dev Faithful stand-in for the Trust Wallet "Biz" EIP-7702 delegate (secp256k1 path).
///      Mirrors the verified contract: wraps `hash` in Biz's own EIP-712 domain, then requires
///      `recover(...) == address(this)`. In real 7702, `address(this)` is the delegating EOA, so
///      the EOA's own key must sign. We reproduce that by etching this runtime onto an EOA address.
contract MockTrustWalletBizK1 {
  bytes4 private constant MAGIC = 0x1626ba7e;
  bytes32 private constant BIZ_MSG_HASH = keccak256("BizMessage(bytes32 hash)");
  bytes32 private constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  function _domainSeparator() internal view returns (bytes32) {
    return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Biz"), keccak256("1.0.0"), block.chainid, address(this)));
  }

  /// @notice Same EIP-712 wrap the real Biz delegate applies (`_getEncodedMsgHash`).
  function getEncodedMsgHash(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(BIZ_MSG_HASH, hash))));
  }

  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
    return ECDSA.recover(getEncodedMsgHash(hash), signature) == address(this) ? MAGIC : bytes4(0xffffffff);
  }
}

/// @title Smart-contract-wallet vault owners (secp256k1) — Phase A
/// @notice Proves the current #145 `SignatureChecker`-based automator operates a PrivateVault whose
///         owner is a Coinbase Smart Wallet (address owner) or a Trust Wallet Biz (EIP-7702) account.
contract PrivateVaultAutomatorSmartWalletOwnerTest is TestCommon {
  AutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  SmartWalletMockStrategy internal strategy;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);

  // Coinbase owner: the EOA key that the smart wallet trusts as owner.
  uint256 internal constant CB_OWNER_PK = 0xC0FFEE01;
  address internal cbOwnerKey;
  MockCoinbaseSmartWalletK1 internal coinbaseWallet;

  // Biz owner: the EOA that delegates to Biz (has both a key and, via etch, code).
  uint256 internal constant BIZ_OWNER_PK = 0xB12002;
  address internal bizAccount;

  uint256 internal allowanceNonce;

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("RPC_URL"), 27_448_360));

    strategy = new SmartWalletMockStrategy();
    configManager = new PrivateConfigManager();

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new AutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();

    // --- Coinbase Smart Wallet owner (deployed contract account) ---
    cbOwnerKey = vm.addr(CB_OWNER_PK);
    coinbaseWallet = new MockCoinbaseSmartWalletK1(cbOwnerKey);

    // --- Trust Wallet Biz (EIP-7702) owner: an EOA carrying the Biz runtime code ---
    bizAccount = vm.addr(BIZ_OWNER_PK);
    MockTrustWalletBizK1 bizImpl = new MockTrustWalletBizK1();
    vm.etch(bizAccount, address(bizImpl).code); // simulate 7702: address(this) == bizAccount at call time
  }

  // ============================ helpers ============================

  function _deployVault(address vaultOwner) internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(vaultOwner, address(configManager), "SmartWallet Vault");
  }

  function _agentAllowance(address vault, uint64 expiration) internal returns (bytes memory encoded, bytes32 digest) {
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory allowance =
      AgentAllowanceStructHash.AgentAllowance(vault, uint64(block.timestamp + allowanceNonce), expiration);
    encoded = abi.encode(allowance);
    digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
  }

  function _orderDigest() internal view returns (bytes memory encoded, bytes32 digest) {
    LpUniV3StructHash.Order memory emptyOrder;
    encoded = abi.encode(emptyOrder);
    digest = automator.hashTypedDataV4(LpUniV3StructHash._hash(emptyOrder));
  }

  function _multicall()
    internal
    view
    returns (
      address[] memory targets,
      uint256[] memory callValues,
      bytes[] memory data,
      IPrivateCommon.CallType[] memory callTypes
    )
  {
    targets = new address[](1);
    callValues = new uint256[](1);
    data = new bytes[](1);
    callTypes = new IPrivateCommon.CallType[](1);
    targets[0] = address(strategy);
    data[0] = abi.encodeWithSelector(SmartWalletMockStrategy.setValue.selector, 42);
    callTypes[0] = IPrivateCommon.CallType.CALL;
  }

  // Build a signature that `coinbaseWallet` accepts: SignatureWrapper over replaySafeHash(digest).
  function _signAsCoinbase(bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, coinbaseWallet.replaySafeHash(digest));
    MockCoinbaseSmartWalletK1.SignatureWrapper memory wrapper =
      MockCoinbaseSmartWalletK1.SignatureWrapper({ ownerIndex: 0, signatureData: abi.encodePacked(r, s, v) });
    return abi.encode(wrapper);
  }

  // Build a signature that the Biz-delegated EOA accepts: 65-byte ECDSA over Biz's wrapped hash.
  function _signAsBiz(bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, MockTrustWalletBizK1(bizAccount).getEncodedMsgHash(digest));
    return abi.encodePacked(r, s, v);
  }

  // ============================ Coinbase (address owner) ============================

  function test_coinbase_ownerIsContract() public view {
    assertGt(address(coinbaseWallet).code.length, 0);
  }

  function test_coinbase_agentAllowance_success() public {
    PrivateVault vault = _deployVault(address(coinbaseWallet));
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault), uint64(block.timestamp + 3600));
    bytes memory sig = _signAsCoinbase(digest, CB_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);

    assertEq(strategy.value(), 42);
  }

  function test_coinbase_userOrder_success() public {
    PrivateVault vault = _deployVault(address(coinbaseWallet));
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signAsCoinbase(digest, CB_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);

    assertEq(strategy.value(), 42);
  }

  function test_coinbase_cancelOrder_success() public {
    _deployVault(address(coinbaseWallet));
    bytes32 orderHash = keccak256("coinbase-order-1");
    bytes memory sig = _signAsCoinbase(orderHash, CB_OWNER_PK);

    vm.prank(address(coinbaseWallet));
    automator.cancelOrder(orderHash, sig);

    assertTrue(automator.isOrderCancelled(orderHash));
  }

  function test_coinbase_wrongSigner_reverts() public {
    PrivateVault vault = _deployVault(address(coinbaseWallet));
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault), uint64(block.timestamp + 3600));
    bytes memory badSig = _signAsCoinbase(digest, 0xDEAD); // not the wallet's owner key

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }

  function test_coinbase_expiredAllowance_reverts() public {
    PrivateVault vault = _deployVault(address(coinbaseWallet));
    vm.warp(block.timestamp + 10_000);
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault), uint64(block.timestamp - 1));
    bytes memory sig = _signAsCoinbase(digest, CB_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
  }

  // ============================ Trust Wallet Biz (EIP-7702) ============================

  function test_biz_ownerHasCodeAndKey() public view {
    assertGt(bizAccount.code.length, 0); // delegated (7702-style)
    assertEq(bizAccount, vm.addr(BIZ_OWNER_PK)); // and still controlled by its key
  }

  function test_biz_agentAllowance_success() public {
    PrivateVault vault = _deployVault(bizAccount);
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault), uint64(block.timestamp + 3600));
    bytes memory sig = _signAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);

    assertEq(strategy.value(), 42);
  }

  function test_biz_userOrder_success() public {
    PrivateVault vault = _deployVault(bizAccount);
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);

    assertEq(strategy.value(), 42);
  }

  function test_biz_cancelOrder_success() public {
    _deployVault(bizAccount);
    bytes32 orderHash = keccak256("biz-order-1");
    bytes memory sig = _signAsBiz(orderHash, BIZ_OWNER_PK);

    vm.prank(bizAccount);
    automator.cancelOrder(orderHash, sig);

    assertTrue(automator.isOrderCancelled(orderHash));
  }

  function test_biz_wrongSigner_reverts() public {
    PrivateVault vault = _deployVault(bizAccount);
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault), uint64(block.timestamp + 3600));
    bytes memory badSig = _signAsBiz(digest, 0xBAD5); // not bizAccount's key

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }
}
