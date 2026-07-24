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

interface ICoinbaseSmartWalletFactory {
  function createAccount(bytes[] calldata owners, uint256 nonce) external payable returns (address account);
}

interface ICoinbaseSmartWallet {
  function replaySafeHash(bytes32 hash) external view returns (bytes32);

  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

contract ForkMockStrategy {
  uint256 public value;

  function setValue(uint256 _value) external {
    value = _value;
  }
}

contract ForkAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) {}

  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @title Real-bytecode fork tests: PrivateVault owned by an ACTUAL Coinbase Smart Wallet (Base)
/// @notice Deploys real Coinbase Smart Wallets via the canonical Base factory (address + passkey
///         owners) and proves the current #145 automator operates a vault they own.
///         Run networked + under osaka for the passkey P256 precompile:
///           RPC_URL=https://mainnet.base.org forge test \
///             --match-contract PrivateVaultSmartWalletOwnerFork --evm-version osaka -vv
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

contract PrivateVaultSmartWalletOwnerForkTest is TestCommon {
  ICoinbaseSmartWalletFactory internal constant COINBASE_FACTORY =
    ICoinbaseSmartWalletFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);
  uint256 internal constant P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;

  ForkAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  ForkMockStrategy internal strategy;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant CB_OWNER_PK = 0xC0FFEE01;
  uint256 internal constant PASSKEY_PK = 0xB0B;
  uint256 internal allowanceNonce;

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("RPC_URL"), 27_448_360));
    require(address(COINBASE_FACTORY).code.length > 0, "coinbase factory not on fork");

    strategy = new ForkMockStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new ForkAutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
  }

  // --------------------------- helpers ---------------------------

  function _skipIfNoP256() internal {
    bytes32 h = keccak256("p256-liveness");
    (bytes32 r, bytes32 s) = vm.signP256(PASSKEY_PK, h);
    uint256 sU = uint256(s) > P256_N / 2 ? P256_N - uint256(s) : uint256(s);
    (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
    (bool ok, bytes memory out) = address(0x100).staticcall(
      abi.encodePacked(h, r, bytes32(sU), bytes32(x), bytes32(y))
    );
    if (!(ok && out.length == 32 && abi.decode(out, (uint256)) == 1)) vm.skip(true);
  }

  function _deployVault(address owner_) internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(owner_, address(configManager), "Fork SmartWallet Vault");
  }

  function _agentAllowance(address vault) internal returns (bytes memory encoded, bytes32 digest) {
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a = AgentAllowanceStructHash.AgentAllowance(
      vault,
      uint64(block.timestamp + allowanceNonce),
      uint64(block.timestamp + 3600)
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
    d[0] = abi.encodeWithSelector(ForkMockStrategy.setValue.selector, 42);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function _createCoinbaseAddressOwner(uint256 pk, uint256 salt) internal returns (address acct) {
    bytes[] memory owners = new bytes[](1);
    owners[0] = abi.encode(vm.addr(pk));
    acct = COINBASE_FACTORY.createAccount(owners, salt);
  }

  function _createCoinbasePasskeyOwner(uint256 pk, uint256 salt) internal returns (address acct) {
    (uint256 x, uint256 y) = vm.publicKeyP256(pk);
    bytes[] memory owners = new bytes[](1);
    owners[0] = abi.encode(x, y);
    acct = COINBASE_FACTORY.createAccount(owners, salt);
  }

  function _signCoinbaseAddress(address acct, bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ICoinbaseSmartWallet(acct).replaySafeHash(digest));
    return abi.encode(SignatureWrapper({ ownerIndex: 0, signatureData: abi.encodePacked(r, s, v) }));
  }

  function _signCoinbasePasskey(address acct, bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    bytes32 rsh = ICoinbaseSmartWallet(acct).replaySafeHash(digest);
    string memory challengeB64 = Base64.encode(abi.encode(rsh), true, true);
    string memory clientDataJSON = string.concat(
      '{"type":"webauthn.get","challenge":"',
      challengeB64,
      '","origin":"https://keys.coinbase.com"}'
    );
    bytes memory authenticatorData = abi.encodePacked(keccak256("rpId"), bytes1(0x05), bytes4(uint32(1)));
    bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
    (bytes32 r, bytes32 s) = vm.signP256(pk, messageHash);
    uint256 sU = uint256(s) > P256_N / 2 ? P256_N - uint256(s) : uint256(s);

    WebAuthnAuth memory auth = WebAuthnAuth({
      authenticatorData: authenticatorData,
      clientDataJSON: clientDataJSON,
      challengeIndex: 23,
      typeIndex: 1,
      r: uint256(r),
      s: sU
    });
    return abi.encode(SignatureWrapper({ ownerIndex: 0, signatureData: abi.encode(auth) }));
  }

  // --------------------------- Coinbase address owner ---------------------------

  function test_fork_coinbase_addressOwner_agentAllowance() public {
    address acct = _createCoinbaseAddressOwner(CB_OWNER_PK, 100);
    assertGt(acct.code.length, 0);
    PrivateVault vault = _deployVault(acct);

    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _signCoinbaseAddress(acct, digest, CB_OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();

    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_coinbase_addressOwner_userOrder() public {
    address acct = _createCoinbaseAddressOwner(CB_OWNER_PK, 101);
    PrivateVault vault = _deployVault(acct);

    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signCoinbaseAddress(acct, digest, CB_OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();

    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }

  // --------------------------- Coinbase passkey owner (real WebAuthn) ---------------------------

  function test_fork_coinbase_passkeyOwner_agentAllowance() public {
    _skipIfNoP256();
    address acct = _createCoinbasePasskeyOwner(PASSKEY_PK, 200);
    assertGt(acct.code.length, 0);
    PrivateVault vault = _deployVault(acct);

    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _signCoinbasePasskey(acct, digest, PASSKEY_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();

    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_coinbase_passkeyOwner_userOrder() public {
    _skipIfNoP256();
    address acct = _createCoinbasePasskeyOwner(PASSKEY_PK, 201);
    PrivateVault vault = _deployVault(acct);

    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signCoinbasePasskey(acct, digest, PASSKEY_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();

    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }
}
