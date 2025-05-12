// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../core/IVault.sol";

interface IMerklAutomator is ICommon {
  error InvalidAssetStrategy();

  function executeAllocate(
    IVault vault,
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    uint64 gasFeeX64,
    bytes calldata allocateCalldata,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;
}
