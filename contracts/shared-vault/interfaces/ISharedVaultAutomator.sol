// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./ISharedCommon.sol";
import "./ISharedVault.sol";

interface ISharedVaultAutomator is ISharedCommon {
  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes32 hash, bytes signature);

  /// @notice Execute actions against a vault using a long-lived AgentAllowance signature.
  /// @dev **Security note**: the AgentAllowance struct commits only to (vault, signatureTime,
  ///      expirationTime). It does NOT restrict which strategies, targets, or calldata the
  ///      operator may use — any whitelisted operation on the vault is permitted until expiry.
  ///      This is a broad delegation by design; vault owners should use short expiration
  ///      windows and `cancelOrder` for early revocation. `executeWithUserOrder` is NOT a more
  ///      restricted alternative (it is also reusable and does not bind the actions); this
  ///      allowance is in fact the narrower primitive, as it commits to a specific vault and expiry.
  /// @param vault Vault to operate on
  /// @param actions Same shape as `ISharedVault.execute` (`CallType.DELEGATECALL` for strategies, `CALL` for swaps)
  /// @param abiEncodedAgentAllowance ABI-encoded AgentAllowance struct
  /// @param signature Vault owner's EIP-712 signature over the AgentAllowance
  function executeWithAgentAllowance(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes memory abiEncodedAgentAllowance,
    bytes memory signature
  ) external;

  /// @notice Execute actions against a vault using a user order signature signed by the vault owner.
  /// @dev **Security note**: like `executeWithAgentAllowance`, this is broad operator delegation — NOT a
  ///      one-time or per-action authorization. The order signature is checked only for authenticity and
  ///      not-cancelled state: it is NOT consumed (the same order may be re-executed until the owner
  ///      calls `cancelOrder`), it does NOT bind the `actions` the operator submits, and the order struct
  ///      carries no vault field (one signature is valid against every vault the same owner controls).
  ///      The `OPERATOR_ROLE` holder is trusted to choose appropriate `actions`; the vault's own
  ///      whitelist checks bound what those actions can do. Owners should sign sparingly and revoke via
  ///      `cancelOrder`. For vault- and time-bounded delegation, prefer `executeWithAgentAllowance`.
  /// @param vault Vault to operate on
  /// @param actions Same shape as `ISharedVault.execute`
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeWithUserOrder(
    ISharedVault vault,
    ISharedVault.Action[] calldata actions,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  /// @notice Cancel an order identified by its EIP-712 digest so it cannot be executed.
  /// @dev Cancellation is keyed on the digest, not the raw signature bytes, so that
  ///      EIP-1271 multisig wallets (which may produce different signature bytes for the
  ///      same digest each time) cannot bypass cancellation with a fresh signature.
  ///      Note: cancellation is only permanent if the owner does not re-sign a struct with
  ///      identical field values (which would produce the same digest). AgentAllowance
  ///      includes `signatureTime` and `expirationTime` as entropy; choosing new values
  ///      yields a distinct hash that is not cancelled.
  /// @param hash EIP-712 digest that was signed
  /// @param signature The signature to cancel (must have been signed by msg.sender)
  function cancelOrder(bytes32 hash, bytes memory signature) external;

  /// @notice Check whether `actor` has cancelled the order identified by its EIP-712 `hash`.
  /// @dev Cancellation is scoped to the canceller (keyed on `(actor, hash)`), so this is per-actor:
  ///      pass the order's signer (the vault owner) to learn whether a live order has been revoked.
  ///      A different `actor` self-cancelling the same `hash` does not affect the owner's order.
  function isOrderCancelled(address actor, bytes32 hash) external view returns (bool);

  /// @notice Grant operator role to an address
  function grantOperator(address operator) external;

  /// @notice Revoke operator role from an address
  function revokeOperator(address operator) external;
}
