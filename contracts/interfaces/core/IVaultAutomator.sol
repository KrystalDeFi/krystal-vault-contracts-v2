// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../core/IVault.sol";

interface IVaultAutomator is ICommon {
  error InvalidOperator();

  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes order, bytes signature);

  function executeAllocate(
    IVault vault,
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    uint64 gasFeeX64,
    bytes calldata allocateCalldata,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  function executeSweepToken(IVault vault, address[] memory tokens) external;

  function executeSweepERC721(IVault vault, address[] memory tokens, uint256[] memory tokenIds) external;

  function executeSweepERC1155(
    IVault vault,
    address[] memory tokens,
    uint256[] memory tokenIds,
    uint256[] memory amounts
  ) external;

  function cancelOrder(bytes calldata abiEncodedUserOrder, bytes calldata orderSignature) external;

  function isOrderCancelled(bytes calldata orderSignature) external view returns (bool);

  function grantOperator(address operator) external;

  function revokeOperator(address operator) external;
}
