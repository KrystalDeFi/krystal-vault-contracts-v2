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
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../contracts/common/libraries/strategies/AgentAllowanceStructHash.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/common/libraries/strategies/LpUniV3StructHash.sol";

contract IntgStrategy {
  uint256 public value;
  function setValue(uint256 _value) external { value = _value; }
}

contract IntgAutomatorHarness is PrivateVaultAutomator {
  constructor(address _owner, address[] memory _operators) PrivateVaultAutomator(_owner, _operators) { }
  function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) { return _hashTypedDataV4(structHash); }
}

contract IntgWrapped7702Delegate {
  bytes4 constant MAGIC = 0x1626ba7e;
  function wrap(bytes32 hash) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Delegate:", block.chainid, address(this), hash));
  }
  function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
    (address rec, ECDSA.RecoverError err, ) = ECDSA.tryRecover(wrap(hash), sig);
    return (err == ECDSA.RecoverError.NoError && rec == address(this)) ? MAGIC : bytes4(0xffffffff);
  }
}

contract PrivateVaultAutomator7702IntegrationTest is Test {
  IntgAutomatorHarness internal automator;
  PrivateConfigManager internal configManager;
  IntgStrategy internal strategy;
  address internal constant OPERATOR = address(0xABCD);
  address internal constant ADMIN = address(0xAD);
  uint256 internal constant OWNER_PK = 0x7702F00D;
  address internal owner7702;

  function setUp() public {
    strategy = new IntgStrategy();
    configManager = new PrivateConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    configManager.initialize(ADMIN, targets, new address[](0), ADMIN);
    address[] memory operators = new address[](1);
    operators[0] = OPERATOR;
    automator = new IntgAutomatorHarness(ADMIN, operators);
    vm.startPrank(ADMIN);
    address[] memory automators = new address[](1);
    automators[0] = address(automator);
    configManager.setWhitelistCallers(automators, true);
    vm.stopPrank();
    owner7702 = vm.addr(OWNER_PK);
    IntgWrapped7702Delegate impl = new IntgWrapped7702Delegate();
    vm.etch(owner7702, address(impl).code);
  }

  function _vault() internal returns (PrivateVault v) {
    v = new PrivateVault();
    v.initialize(owner7702, address(configManager), "7702 integration vault");
  }

  function _multicall(uint256 val)
    internal view
    returns (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct)
  {
    t = new address[](1); cv = new uint256[](1); d = new bytes[](1); ct = new IPrivateCommon.CallType[](1);
    t[0] = address(strategy);
    d[0] = abi.encodeWithSelector(IntgStrategy.setValue.selector, val);
    ct[0] = IPrivateCommon.CallType.CALL;
  }

  function _rawSign(bytes32 digest) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);
    return abi.encodePacked(r, s, v);
  }

  // Reusable agent allowance signed once, replayed on multiple operator executions until expiry.
  function test_lifecycle_reusableAllowance_multipleExecutions() public {
    PrivateVault vault = _vault();
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(address(vault), uint64(block.timestamp + 1), uint64(block.timestamp + 3600));
    bytes memory encoded = abi.encode(a);
    bytes32 digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
    bytes memory sig = _rawSign(digest);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(7);
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 7);

    (t, cv, d, ct) = _multicall(9);
    vm.prank(OPERATOR);
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
    assertEq(strategy.value(), 9); // same signature reused
  }

  // Non-operator cannot execute even with a valid owner signature.
  function test_nonOperator_reverts() public {
    PrivateVault vault = _vault();
    AgentAllowanceStructHash.AgentAllowance memory a =
      AgentAllowanceStructHash.AgentAllowance(address(vault), uint64(block.timestamp + 1), uint64(block.timestamp + 3600));
    bytes memory encoded = abi.encode(a);
    bytes32 digest = automator.hashTypedDataV4(AgentAllowanceStructHash._hash(encoded));
    bytes memory sig = _rawSign(digest);
    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(7);
    bytes32 operatorRoleHash = automator.OPERATOR_ROLE_HASH();
    vm.prank(address(0xBEEF));
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(0xBEEF), operatorRoleHash)
    );
    automator.executeMulticallWithAgentAllowance(IPrivateVault(address(vault)), t, cv, d, ct, encoded, sig);
  }

  // Cancelling an order makes a subsequent execute with that order revert.
  function test_cancelledOrder_blocksExecution() public {
    PrivateVault vault = _vault();
    LpUniV3StructHash.Order memory emptyOrder;
    bytes memory encodedOrder = abi.encode(emptyOrder);
    bytes32 digest = automator.hashTypedDataV4(LpUniV3StructHash._hash(emptyOrder));
    bytes memory sig = _rawSign(digest);

    vm.prank(owner7702);
    automator.cancelOrder(digest, sig);

    (address[] memory t, uint256[] memory cv, bytes[] memory d, IPrivateCommon.CallType[] memory ct) = _multicall(5);
    vm.prank(OPERATOR);
    vm.expectRevert(IPrivateVaultAutomator.OrderCancelled.selector);
    automator.executeMulticallWithUserOrder(IPrivateVault(address(vault)), t, cv, d, ct, encodedOrder, sig);
  }
}
