// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../interfaces/ISharedVaultAutomator.sol";
import "../../private-vault/core/CustomEIP712.sol";
import "../../common/libraries/strategies/AgentAllowanceStructHash.sol";
import "../../common/Withdrawable.sol";

contract SharedVaultAutomator is CustomEIP712, AccessControl, Pausable, Withdrawable, ISharedVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) CustomEIP712("SharedVaultAutomator", "1.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  /// @inheritdoc ISharedVaultAutomator
  function executeWithAgentAllowance(
    ISharedVault vault,
    Operation[] calldata operations,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external payable override onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateAgentAllowance(abiEncodedAgentAllowance, signature, address(vault));
    _executeOperations(vault, operations);
  }

  /// @inheritdoc ISharedVaultAutomator
  /// @dev Uses the same AgentAllowance struct but marks the signature as consumed after execution,
  ///      making it a one-time-use credential unlike the reusable AgentAllowance flow.
  function executeWithUserOrder(
    ISharedVault vault,
    Operation[] calldata operations,
    bytes calldata abiEncodedAgentAllowance,
    bytes calldata signature
  ) external payable override onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateAgentAllowance(abiEncodedAgentAllowance, signature, address(vault));
    // Mark consumed before execution to prevent reentrancy replay
    _cancelledOrder[keccak256(signature)] = true;
    _executeOperations(vault, operations);
  }

  /// @inheritdoc ISharedVaultAutomator
  function cancelOrder(bytes32 hash, bytes memory signature) external override {
    // SignatureChecker: for EOA checks ECDSA recovery; for multisig calls EIP-1271.isValidSignature
    require(SignatureChecker.isValidSignatureNow(_msgSender(), hash, signature), InvalidSignature());
    _cancelledOrder[keccak256(signature)] = true;
    emit CancelOrder(_msgSender(), hash, signature);
  }

  /// @inheritdoc ISharedVaultAutomator
  function isOrderCancelled(bytes calldata signature) external view override returns (bool) {
    return _cancelledOrder[keccak256(signature)];
  }

  /// @inheritdoc ISharedVaultAutomator
  function grantOperator(address operator) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @inheritdoc ISharedVaultAutomator
  function revokeOperator(address operator) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Pause the automator
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpause the automator
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  /// @inheritdoc Withdrawable
  function _checkWithdrawPermission() internal view override {
    _checkRole(DEFAULT_ADMIN_ROLE);
  }

  receive() external payable {}

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  // ─── Internal helpers ────────────────────────────────────────────────────

  function _validateAgentAllowance(
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature,
    address vault
  ) internal view {
    AgentAllowanceStructHash.AgentAllowance memory allowance =
      abi.decode(abiEncodedAgentAllowance, (AgentAllowanceStructHash.AgentAllowance));
    require(allowance.vault == vault, InvalidSignature());
    require(allowance.expirationTime >= block.timestamp, InvalidSignature());
    // Use SignatureChecker to support both EOA (ECDSA) and smart contract wallets (EIP-1271 multisig)
    bytes32 digest = _hashTypedDataV4(AgentAllowanceStructHash._hash(abiEncodedAgentAllowance));
    address owner = ISharedVault(vault).vaultOwner();
    require(SignatureChecker.isValidSignatureNow(owner, digest, signature), InvalidSignature());
    require(!_cancelledOrder[keccak256(signature)], OrderCancelled());
  }

  function _executeOperations(ISharedVault vault, Operation[] calldata operations) internal {
    uint256 totalEth;
    for (uint256 i; i < operations.length;) {
      if (operations[i].opType == OpType.EXECUTE) {
        totalEth += operations[i].value;
      }
      unchecked { i++; }
    }
    require(totalEth == msg.value, InvalidAmount());

    for (uint256 i; i < operations.length;) {
      Operation calldata op = operations[i];
      bool isStrategy = op.opType == OpType.EXECUTE;
      ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
      actions[0] = ISharedVault.Action(op.target, op.data, op.value, isStrategy);
      vault.execute{ value: op.value }(actions);
      unchecked { i++; }
    }
  }
}
