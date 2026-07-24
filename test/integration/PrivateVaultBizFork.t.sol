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

contract BizForkMockStrategy {
  uint256 public value;

  function setValue(uint256 _value) external {
    value = _value;
  }
}

contract BizForkAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }

  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @title Real-bytecode fork test: PrivateVault owned by an EIP-7702 account delegated to the ACTUAL
///        Trust Wallet "Biz" implementation on Ethereum mainnet.
/// @notice `BIZ_7702_ACCOUNT` (0x9aed…) is a real user 7702 account whose code is a 23-byte
///         delegation designator pointing at the Biz implementation. We copy that designator onto a
///         test EOA (whose key we control) so calls execute the real Biz impl with address(this)==EOA
///         — the genuine 7702 condition. Biz validates a 65-byte ECDSA sig over its EIP-712-wrapped
///         hash and requires recover(...) == address(this).
///         Pinned to a fixed mainnet block where the delegation is present, so the fork is HERMETIC:
///         that block is committed under test/fixtures/rpc-cache/mainnet and replayed offline. Runs
///         under --evm-version osaka (EIP-7702). Self-skips only if MAINNET_RPC_URL is unset or the
///         delegation is absent at the pinned block.
///           MAINNET_RPC_URL=https://mainnet.gateway.tenderly.co \
///             forge test --match-contract PrivateVaultBizFork --evm-version osaka -vv
contract PrivateVaultBizForkTest is TestCommon {
  // A real Trust Wallet Biz 7702 account on mainnet (delegation designator → Biz implementation).
  address internal constant BIZ_7702_ACCOUNT = 0x9AED5B111E3c522BA1B938d7b7bD47AfE85CFA74;

  // Pinned mainnet block at which BIZ_7702_ACCOUNT is 7702-delegated. Cached under
  // test/fixtures/rpc-cache/mainnet/<block> so this fork replays offline (deterministic + hermetic).
  // To move it: pick a recent block where eth_getCode(BIZ_7702_ACCOUNT) is a 23-byte 0xef0100…
  // designator, then run scripts/regen-fork-cache.sh.
  uint256 internal constant BIZ_FORK_BLOCK = 25_596_137;

  // Verified Biz EIP-712 constants (from on-chain source).
  bytes32 internal constant BIZ_MSG_HASH = 0x31322a37c2a66b24e1088197e5b24fcc050625c13d4b84c3eaa6a8be5270321d; // keccak("Biz(bytes32 msgHash)")
  bytes32 internal constant BIZ_DOMAIN_SEPARATOR_HASH =
    0xd87cd6ef79d4e2b95e15ce8abf732db51ec771f1ca2edccf22a46c729ac56472; // keccak(EIP712Domain(...,bytes32 salt))
  bytes32 internal constant BIZ_HASH = 0x906754a21e6afe7233c7ccce2787110e84157e1cbaa80e58656dff779193a5cd; // keccak("Biz")
  bytes32 internal constant VERSION_HASH = 0x15124d26d1272f8d4d5266a24ca397811f414b8cd05a53b26b745f63af5ae2fc; // keccak("v1.0.0")

  BizForkAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  BizForkMockStrategy internal strategy;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant BIZ_OWNER_PK = 0xB12002;
  address internal bizAccount; // our test EOA, delegated to the Biz impl
  address internal bizImpl; // the Biz implementation (designator target); == singletonSalt
  bool internal live;
  uint256 internal allowanceNonce;

  function setUp() public {
    string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
    if (bytes(rpc).length == 0) return; // no mainnet RPC → tests skip
    vm.createSelectFork(rpc, BIZ_FORK_BLOCK); // pinned + cached → hermetic offline replay

    bytes memory designator = BIZ_7702_ACCOUNT.code;
    if (designator.length != 23) return; // account not (or no longer) 7702-delegated → skip
    address impl;
    assembly {
      impl := shr(96, mload(add(designator, 35))) // 0xef0100 ++ impl(20)
    }
    bizImpl = impl;
    live = true;

    // Put a controllable EOA under the same real Biz delegation.
    bizAccount = vm.addr(BIZ_OWNER_PK);
    vm.etch(bizAccount, designator);

    strategy = new BizForkMockStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new BizForkAutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
  }

  function _skipUnlessLive() internal {
    if (!live) vm.skip(true);
  }

  // Reconstruct Biz's `_getEncodedMsgHash(BIZ_MSG_HASH, digest)`: address(this) == the delegating
  // EOA, singletonSalt == the Biz implementation address (immutable baked at the impl's deploy).
  function _bizWrappedHash(bytes32 digest) internal view returns (bytes32) {
    bytes32 domainSeparator = keccak256(
      abi.encode(
        BIZ_DOMAIN_SEPARATOR_HASH, BIZ_HASH, VERSION_HASH, block.chainid, bizAccount, bytes32(uint256(uint160(bizImpl)))
      )
    );
    bytes32 messageHash = keccak256(abi.encode(BIZ_MSG_HASH, digest));
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator, messageHash));
  }

  function _signAsBiz(bytes32 digest, uint256 pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _bizWrappedHash(digest));
    return abi.encodePacked(r, s, v);
  }

  function _deployVault() internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(bizAccount, address(configManager), "Biz 7702 Vault");
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
    d[0] = abi.encodeWithSelector(BizForkMockStrategy.setValue.selector, 42);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function test_fork_biz7702_ownerDelegatedToRealBiz() public {
    _skipUnlessLive();
    assertEq(bizAccount.code.length, 23); // 7702 designator
    assertTrue(bizImpl != address(0));
  }

  function test_fork_biz7702_agentAllowance() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _signAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_biz7702_userOrder() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _signAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_biz7702_wrongSigner_reverts() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory badSig = _signAsBiz(digest, 0xBAD5); // correct wrapped hash, wrong key

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }

  // Sign the RAW automator digest with the delegating EOA's key (no Biz EIP-712 wrap).
  // SignatureChecker rejected this; SignatureValidator accepts it via the ECDSA leg.
  function _rawSignAsBiz(bytes32 digest, uint256 pk) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    return abi.encodePacked(r, s, v);
  }

  function test_fork_biz7702_rawEoaSig_agentAllowance() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _rawSignAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_fork_biz7702_rawEoaSig_userOrder() public {
    _skipUnlessLive();
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _rawSignAsBiz(digest, BIZ_OWNER_PK);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }
}
