// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../interfaces/ISharedCommon.sol";
import "../interfaces/ISharedConfigManager.sol";

library SharedSwapDataSignature {
  bytes32 internal constant STORAGE_SLOT = 0x6ce297c6014d3c10153ad923862990ba409ec008504a76b97755f106d0c7d074;

  struct Layout {
    mapping(bytes32 => bool) consumedDigests;
  }

  struct Envelope {
    bytes swapData;
    address vault;
    uint256 deadline;
    address signer;
    bytes32 nonce;
    bytes signature;
  }

  /// @dev Signed envelope: abi.encode(rawSwapData, vault, deadline, signer, nonce, signature).
  function decode(bytes memory signedSwapData) internal pure returns (Envelope memory envelope) {
    (envelope.swapData, envelope.vault, envelope.deadline, envelope.signer, envelope.nonce, envelope.signature) =
      abi.decode(signedSwapData, (bytes, address, uint256, address, bytes32, bytes));
  }

  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function hash(
    address vault,
    address signer,
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory swapData,
    uint256 deadline,
    bytes32 nonce
  ) internal view returns (bytes32) {
    return keccak256(
      abi.encode(
        block.chainid,
        vault,
        signer,
        swapRouter,
        tokenIn,
        tokenOut,
        amountIn,
        amountOutMin,
        keccak256(swapData),
        deadline,
        nonce
      )
    );
  }

  function verify(
    ISharedConfigManager configManager,
    address expectedVault,
    address swapRouter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory signedSwapData
  ) public returns (bytes memory swapData) {
    Envelope memory envelope = decode(signedSwapData);
    require(envelope.vault == expectedVault, ISharedCommon.InvalidSwapDataSignature());
    require(envelope.deadline >= block.timestamp, ISharedCommon.SwapDataSignatureExpired());
    require(configManager.isWhitelistedSigner(envelope.signer), ISharedCommon.InvalidSwapDataSignature());

    bytes32 digest = hash(
      envelope.vault,
      envelope.signer,
      swapRouter,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      envelope.swapData,
      envelope.deadline,
      envelope.nonce
    );
    Layout storage l = layout();
    require(!l.consumedDigests[digest], ISharedCommon.SwapDataSignatureAlreadyUsed());
    require(
      SignatureChecker.isValidSignatureNow(envelope.signer, digest, envelope.signature),
      ISharedCommon.InvalidSwapDataSignature()
    );
    l.consumedDigests[digest] = true;

    return envelope.swapData;
  }
}
