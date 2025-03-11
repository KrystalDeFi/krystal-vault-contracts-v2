// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../ICommon.sol";

interface IVaultZapper is ICommon {
  function swapAndDeposit() external;

  function withdrawAndSwap() external;
}
