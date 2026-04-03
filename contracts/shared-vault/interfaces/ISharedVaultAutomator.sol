// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";
import "./ISharedVault.sol";

interface ISharedVaultAutomator is ISharedCommon {
  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes32 hash, bytes signature);

  /// @notice Operation type for the automator
  enum OpType {
    EXECUTE,
    SWAP
  }

  /// @notice A single operation to execute against a vault
  struct Operation {
    OpType opType;
    /// @dev For EXECUTE: the strategy address; for SWAP: the swap aggregator target
    address target;
    /// @dev For EXECUTE: strategy calldata; for SWAP: abi.encode(tokenIn, tokenOut, amountIn, minAmountOut, swapData)
    bytes data;
    uint256 value;
  }

  /// @notice Execute operations against a vault using a long-lived AgentAllowance signature.
  /// @dev **Security note**: the AgentAllowance struct commits only to (vault, signatureTime,
  ///      expirationTime). It does NOT restrict which strategies, targets, or calldata the
  ///      operator may use — any whitelisted operation on the vault is permitted until expiry.
  ///      This is a broad delegation by design; vault owners should use short expiration
  ///      windows and `cancelOrder` for early revocation. For one-time scoped operations,
  ///      prefer `executeWithUserOrder`.
  /// @param vault Vault to operate on
  /// @param operations Operations to execute
  /// @param abiEncodedAgentAllowance ABI-encoded AgentAllowance struct
  /// @param signature Vault owner's EIP-712 signature over the AgentAllowance
  function executeWithAgentAllowance(
    ISharedVault vault,
    Operation[] calldata operations,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external;

  /// @notice Execute operations against a vault using a user order signature.
  /// @param vault Vault to operate on
  /// @param operations Operations to execute
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeWithUserOrder(
    ISharedVault vault,
    Operation[] calldata operations,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  /// @notice Cancel an order so it can never be replayed
  /// @param hash EIP-712 digest that was signed
  /// @param signature The signature to cancel (must have been signed by msg.sender)
  function cancelOrder(bytes32 hash, bytes memory signature) external;

  /// @notice Check whether an order signature has been cancelled
  function isOrderCancelled(bytes calldata signature) external view returns (bool);

  /// @notice Grant operator role to an address
  function grantOperator(address operator) external;

  /// @notice Revoke operator role from an address
  function revokeOperator(address operator) external;
}
