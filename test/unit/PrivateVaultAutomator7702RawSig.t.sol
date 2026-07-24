// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { PrivateVaultAutomator } from "../../contracts/private-vault/core/PrivateVaultAutomator.sol";
import { IPrivateVaultAutomator } from "../../contracts/private-vault/interfaces/core/IPrivateVaultAutomator.sol";
import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { IPrivateVault } from "../../contracts/private-vault/interfaces/core/IPrivateVault.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

contract RawSigMockStrategy {
  uint256 public value;
  function setValue(uint256 _value) external { value = _value; }
}

contract RawSigAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }
  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
    return _hashTypedDataV4(structHash);
  }
}

/// @dev 7702 delegate that ONLY validates a signature over its own EIP-712-wrapped hash — so a RAW
///      signature fails its isValidSignature. Etched onto an EOA to give code + key at one address.
contract Wrapped7702Delegate {
  bytes4 constant MAGIC = 0x1626ba7e;
  function wrap(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Delegate:", block.chainid, address(this), hash));
  }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(wrap(hash), sig);
    return (err == ECDSA.RecoverError.NoError && rec == address(this)) ? MAGIC : bytes4(0xffffffff);
  }
}

/// @title A 7702 vault owner signing the RAW automator digest (the SignatureChecker-rejected case).
contract PrivateVaultAutomator7702RawSigTest is Test {
  RawSigAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  RawSigMockStrategy internal strategy;

  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant OWNER_PK = 0x7702BEEF;
  address internal owner7702;
  uint256 internal allowanceNonce;

  function setUp() public {
    strategy = new RawSigMockStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);

    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new RawSigAutomatorHarness(ADMIN, operators);

    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();

    owner7702 = vm.addr(OWNER_PK);
    Wrapped7702Delegate impl = new Wrapped7702Delegate();
    vm.etch(owner7702, address(impl).code); // 7702: code + key
  }

  function _deployVault() internal returns (PrivateVault vault) {
    vault = new PrivateVault();
    vault.initialize(owner7702, address(configManager), "7702 raw-sig vault");
  }

  function _agentAllowance(address vault) internal returns (bytes memory encoded, bytes32 digest) {
    allowanceNonce++;
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(vault, uint64(block.timestamp + allowanceNonce), uint64(block.timestamp + 3600));
    encoded = abi.encode(a);
    digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
  }

  function _orderDigest() internal view returns (bytes memory encoded, bytes32 digest) {
    LpUniV3StructHash.Order memory emptyOrder;
    encoded = abi.encode(emptyOrder);
    digest = automator.hashTypedDataV4(LpUniV3StructHash._hash(emptyOrder));
  }

  function _rawSign(bytes32 digest, uint256 pk) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    return abi.encodePacked(r, s, v);
  }

  function _multicall()
    internal view
    returns (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct)
  {
    t = new address[](1); cv = new uint256[](1); d = new bytes[](1); ct = new IPrivateCommon.CallType[](1);
    t[0] = address(strategy);
    d[0] = abi.encodeWithSelector(RawSigMockStrategy.setValue.selector, 42);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function test_7702_rawSig_agentAllowance_success() public {
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory sig = _rawSign(digest, OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 42);
  }

  function test_7702_rawSig_userOrder_success() public {
    PrivateVault vault = _deployVault();
    (bytes memory encodedOrder, bytes32 digest) = _orderDigest();
    bytes memory sig = _rawSign(digest, OWNER_PK);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
    assertEq(strategy.value(), 42);
  }

  function test_7702_rawSig_cancelOrder_success() public {
    _deployVault();
    bytes32 orderHash = keccak256("7702-raw-order");
    bytes memory sig = _rawSign(orderHash, OWNER_PK);
    vm.prank(owner7702);
    automator.cancelOrder(orderHash, sig);
    assertTrue(automator.isOrderCancelled(owner7702, orderHash));
  }

  function test_7702_rawSig_wrongKey_reverts() public {
    PrivateVault vault = _deployVault();
    (bytes memory encoded, bytes32 digest) = _agentAllowance(address(vault));
    bytes memory badSig = _rawSign(digest, 0xBAD5);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall();
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.InvalidSignature.selector);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, badSig);
  }
}
