// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../interfaces/core/IPrivateVaultAutomator.sol";
import "./CustomEIP712.sol";
import "../../common/libraries/strategies/AgentAllowanceStructHash.sol";
import "../../common/Withdrawable.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PrivateVaultAutomator is CustomEIP712, AccessControl, Pausable, Withdrawable, IPrivateVaultAutomator {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) CustomEIP712("V3AutomationOrder", "5.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  // @notice Execute a multicall with AgentAllowance signature
  /// @param vault Vault
  /// @param targets Targets to call
  /// @param callValues Call values
  /// @param data Data to pass to the calls
  /// @param callTypes Call types
  /// @param abiEncodedAgentAllowance abi-encoded AgentAllowance
  /// @param signature Signature of the order
  function executeMulticallWithAgentAllowance(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateAgentAllowance(abiEncodedAgentAllowance, signature, address(vault));
    vault.multicall(targets, callValues, data, callTypes);
  }

  /// @notice Execute a multicall with EIP-712 signature verification
  /// @param vault Vault
  /// @param targets Targets to call
  /// @param callValues Call values
  /// @param data Data to pass to the calls
  /// @param callTypes Call types
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeMulticallWithUserOrder(
    IPrivateVault vault,
    address[] calldata targets,
    uint256[] calldata callValues,
    bytes[] calldata data,
    CallType[] calldata callTypes,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(abiEncodedUserOrder, orderSignature, vault.vaultOwner());
    vault.multicall(targets, callValues, data, callTypes);
  }

  function _validateAgentAllowance(
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature,
    address vault
  ) internal view {
    AgentAllowanceStructHash.AgentAllowance memory agentAllowance = abi.decode(
      abiEncodedAgentAllowance,
      (AgentAllowanceStructHash.AgentAllowance)
    );
    require(agentAllowance.vault == address(vault), InvalidSignature());
    require(agentAllowance.expirationTime >= block.timestamp, InvalidSignature());
    address actor = _recoverAgentAllowance(abiEncodedAgentAllowance, signature);
    require(actor == IPrivateVault(vault).vaultOwner(), InvalidSignature());
    require(!_cancelledOrder[keccak256(signature)], OrderCancelled());
  }

  /// @dev Validate the order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  /// @param actor Actor of the order
  function _validateOrder(bytes memory abiEncodedUserOrder, bytes memory orderSignature, address actor) internal view {
    address userAddress = _recoverOrder(abiEncodedUserOrder, orderSignature);
    require(userAddress == actor, InvalidSignature());
    require(!_cancelledOrder[keccak256(orderSignature)], OrderCancelled());
  }

  /// @notice Cancel an order
  /// @param hash Hash of the data to be signed
  /// @param signature Signature of the order
  function cancelOrder(bytes32 hash, bytes memory signature) external {
    require(ECDSA.recover(hash, signature) == msg.sender, InvalidSignature());
    _cancelledOrder[keccak256(signature)] = true;
    emit CancelOrder(msg.sender, hash, signature);
  }

  /// @notice Check if an order is cancelled
  /// @param signature Signature of the order
  /// @return true if the order is cancelled
  function isOrderCancelled(bytes calldata signature) external view returns (bool) {
    return _cancelledOrder[keccak256(signature)];
  }

  /// @notice Grant operator role
  /// @param operator Operator address
  function grantOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Revoke operator role
  /// @param operator Operator address
  function revokeOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Pause the contract
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpause the contract
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
}
