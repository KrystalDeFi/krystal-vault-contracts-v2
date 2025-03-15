// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../interfaces/core/IVaultZapper.sol";

contract VaultZapper is IVaultZapper {
  constructor() { }

  function swapAndDeposit() external override { }

  function withdrawAndSwap() external override { }
}
