// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";
import "../core/IVault.sol";

interface IVaultAutomator is ICommon {
  error InvalidOperator();

  error InvalidSignature();

  error OrderCancelled();

  event CancelOrder(address user, bytes order, bytes signature);

  struct ExecuteRebalanceParams {
    IVault vault;
    int24 newTickLower;
    int24 newTickUpper;
    uint256 decreaseAmount0Min;
    uint256 decreaseAmount1Min;
    uint256 amount0Min;
    uint256 amount1Min;
    uint16 automatorFee;
    bytes abiEncodedUserOrder;
    bytes orderSignature;
  }

  function executeRebalance(ExecuteRebalanceParams calldata params) external;

  function executeExit(
    IVault vault,
    uint256 amount0Min,
    uint256 amount1Min,
    uint16 automatorFee,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  function executeCompound(
    IVault vault,
    uint256 amount0Min,
    uint256 amount1Min,
    uint16 automatorFee,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external;

  function cancelOrder(bytes calldata abiEncodedUserOrder, bytes calldata orderSignature) external;

  function isOrderCancelled(bytes calldata orderSignature) external view returns (bool);

  function grantOperator(address operator) external;

  function revokeOperator(address operator) external;

  function executeSweepToken(IVault vault, address[] memory tokens) external;

  function executeSweepNFTToken(IVault vault, address[] memory tokens, uint256[] memory tokenIds) external;
}
