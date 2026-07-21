// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";
import { Base64 } from "../helpers/vendored/Base64.sol";

contract PasskeyMockStrategy {
  uint256 public value;

  function setValue(uint256 _value) external {
    value = _value;
  }
}

contract PasskeyAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }

  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @dev Faithful stand-in for a Coinbase Smart Wallet with a passkey (WebAuthn/P256) owner.
///      Mirrors the real contract + webauthn-sol: SignatureWrapper wraps a WebAuthnAuth; the
///      challenge is bound to `replaySafeHash(hash)` inside clientDataJSON; the P256 signature is
///      verified over sha256(authenticatorData || sha256(clientDataJSON)) via the 0x100 precompile.
contract MockCoinbaseSmartWalletPasskey {
  struct SignatureWrapper {
    uint256 ownerIndex;
    bytes signatureData;
  }

  struct WebAuthnAuth {
    bytes authenticatorData;
    string clientDataJSON;
    uint256 challengeIndex;
    uint256 typeIndex;
    uint256 r;
    uint256 s;
  }

  bytes4 private constant MAGIC = 0x1626ba7e;
  bytes4 private constant FAIL = 0xffffffff;
  bytes32 private constant MESSAGE_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
  bytes32 private constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  uint256 private constant P256_N_DIV_2 = 0x7FFFFFFF800000007FFFFFFFFFFFFFFFDE737D56D38BCF4279DCE5617E3192A8;

  uint256 public immutable pubKeyX;
  uint256 public immutable pubKeyY;

  constructor(uint256 x, uint256 y) {
    pubKeyX = x;
    pubKeyY = y;
  }

  function _domainSeparator() internal view returns (bytes32) {
    return keccak256(
      abi.encode(DOMAIN_TYPEHASH, keccak256("Coinbase Smart Wallet"), keccak256("1"), block.chainid, address(this))
    );
  }

  function replaySafeHash(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(MESSAGE_TYPEHASH, hash))));
  }

  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
    SignatureWrapper memory wrapper = abi.decode(signature, (SignatureWrapper));
    if (wrapper.ownerIndex != 0) return FAIL;
    WebAuthnAuth memory auth = abi.decode(wrapper.signatureData, (WebAuthnAuth));
    bytes memory clientData = bytes(auth.clientDataJSON);

    // 1. "type":"webauthn.get"
    if (!_eqAt(clientData, auth.typeIndex, '"type":"webauthn.get"')) return FAIL;

    // 2. challenge is bound to replaySafeHash(hash)
    bytes memory expectedChallenge =
      bytes(string.concat('"challenge":"', Base64.encode(abi.encode(replaySafeHash(hash)), true, true), '"'));
    if (!_eqAt(clientData, auth.challengeIndex, expectedChallenge)) return FAIL;

    // 3. user-presence flag
    if (auth.authenticatorData[32] & 0x01 != 0x01) return FAIL;

    // 4. low-s + P256 verification over the WebAuthn message hash
    if (auth.s > P256_N_DIV_2) return FAIL;
    bytes32 messageHash = sha256(abi.encodePacked(auth.authenticatorData, sha256(clientData)));
    return _p256Verify(messageHash, auth.r, auth.s) ? MAGIC : FAIL;
  }

  function _p256Verify(bytes32 h, uint256 r, uint256 s) internal view returns (bool) {
    (bool ok, bytes memory out) =
      address(0x100).staticcall(abi.encodePacked(h, bytes32(r), bytes32(s), bytes32(pubKeyX), bytes32(pubKeyY)));
    return ok && out.length == 32 && abi.decode(out, (uint256)) == 1;
  }

  function _eqAt(bytes memory data, uint256 offset, bytes memory expected) internal pure returns (bool) {
    if (offset + expected.length > data.length) return false;
    for (uint256 i = 0; i < expected.length; i++) {
      if (data[offset + i] != expected[i]) return false;
    }
    return true;
  }
}

/// @title Coinbase Smart Wallet PASSKEY (WebAuthn/P256) vault owner — Phase B
/// @notice Runs fully under `--evm-version osaka` (P256 precompile at 0x100); self-skips otherwise.
contract PrivateVaultAutomatorPasskeyOwnerTest is TestCommon {
  PasskeyAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  PasskeyMockStrategy internal strategy;
  MockCoinbaseSmartWalletPasskey internal wallet;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant PASSKEY_PK = 0xB0B; // P256 private scalar
  uint256 internal allowanceNonce;

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("RPC_URL"), 27_448_360));

    strategy = new PasskeyMockStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new PasskeyAutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();

    (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
    wallet = new MockCoinbaseSmartWalletPasskey(x, y);
  }

  // Skip when the P256 precompile is not active (i.e. not run under osaka). Probes with a KNOWN-VALID
  // vector: an inactive precompile and an active-but-invalid one both return empty, so all-zeros can't
  // distinguish them — a valid signature makes an active precompile return the 32-byte `1`.
  function _skipIfNoP256() internal {
    bytes32 h = keccak256("p256-liveness");
    (bytes32 r, bytes32 s) = vm.signP256(PASSKEY_PK, h);
    uint256 sU = uint256(s);
    uint256 n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    if (sU > n / 2) sU = n - sU;
    (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
    (bool ok, bytes memory out) =
      address(0x100).staticcall(abi.encodePacked(h, r, bytes32(sU), bytes32(x), bytes32(y)));
    if (!(ok && out.length == 32 && abi.decode(out, (uint256)) == 1)) vm.skip(true);
  }

  function _deployVault() internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(address(wallet), address(configManager), "Passkey Vault");
  }

  function _agentAllowance(address vault) internal returns (bytes memory encoded, bytes32 digest) {
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a = AgentAllowanceStructHash.AgentAllowance(
      vault, uint64(block.timestamp + allowanceNonce), uint64(block.timestamp + 3600)
    );
    encoded = abi.encode(a);
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
    returns (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct)
  {
    t = new address[](1);
    cv = new uint256[](1);
    d = new bytes[](1);
    ct = new IPrivateCommon.CallType[](1);
    t[0] = address(strategy);
    d[0] = abi.encodeWithSelector(PasskeyMockStrategy.setValue.selector, 42);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  // Build a real WebAuthn assertion over the wallet's replay-safe hash of `digest`.
  function _signAsPasskey(bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    string memory challengeB64 = Base64.encode(abi.encode(wallet.replaySafeHash(digest)), true, true);
    string memory clientDataJSON = string.concat(
      '{"type":"webauthn.get","challenge":"', challengeB64, '","origin":"https://keys.coinbase.com"}'
    );
    bytes memory authenticatorData = abi.encodePacked(keccak256("rpId"), bytes1(0x05), bytes4(uint32(1))); // UP|UV
    bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));

    (bytes32 r, bytes32 s) = vm.signP256(pk, messageHash);
    uint256 sUint = uint256(s);
    uint256 n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    if (sUint > n / 2) sUint = n - sUint; // enforce low-s

    MockCoinbaseSmartWalletPasskey.WebAuthnAuth memory auth = MockCoinbaseSmartWalletPasskey.WebAuthnAuth({
      authenticatorData: authenticatorData,
      clientDataJSON: clientDataJSON,
      challengeIndex: 23,
      typeIndex: 1,
      r: uint256(r),
      s: sUint
    });
    MockCoinbaseSmartWalletPasskey.SignatureWrapper memory wrapper =
      MockCoinbaseSmartWalletPasskey.SignatureWrapper({ ownerIndex: 0, signatureData: abi.encode(auth) });
    return abi.encode(wrapper);
  }

  function test_passkey_agentAllowance_success() public {
    _skipIfNoP256();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _signAsPasskey(digest, PASSKEY_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_passkey_userOrder_success() public {
    _skipIfNoP256();
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signAsPasskey(digest, PASSKEY_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }

  function test_passkey_cancelOrder_success() public {
    _skipIfNoP256();
    _deployVault();
    bytes32 orderHash = keccak256("passkey-order-1");
    bytes memory sig = _signAsPasskey(orderHash, PASSKEY_PK);
    vm.prank(address(wallet));
    automator.cancelOrder(orderHash, sig);
    assertTrue(automator.isOrderCancelled(address(wallet), orderHash));
  }

  function test_passkey_wrongKey_reverts() public {
    _skipIfNoP256();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory badSig = _signAsPasskey(digest, 0xDEAD); // different P256 key

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }
}
