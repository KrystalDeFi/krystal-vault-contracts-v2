// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../interfaces/ISharedCommon.sol";
import "../interfaces/ISharedConfigManager.sol";

library SharedSwapDataSignature {
  struct Envelope {
    bytes swapData;
    address vault;
    uint256 deadline;
    address signer;
    bytes signature;
  }

  /// @dev Signed swapData envelope:
  ///      abi.encode(bytes rawSwapData, address vault, uint256 deadline, address signer, bytes signature)
  function decode(bytes memory signedSwapData) internal pure returns (Envelope memory envelope) {
    (envelope.swapData, envelope.vault, envelope.deadline, envelope.signer, envelope.signature) =
      abi.decode(signedSwapData, (bytes, address, uint256, address, bytes));
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
    uint256 deadline
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
        deadline
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
  ) public view returns (bytes memory swapData) {
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
      envelope.deadline
    );
    require(
      SignatureChecker.isValidSignatureNow(envelope.signer, digest, envelope.signature),
      ISharedCommon.InvalidSwapDataSignature()
    );

    return envelope.swapData;
  }
}
