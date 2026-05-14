// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/ISharedCommon.sol";
import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedStrategy.sol";
import "../interfaces/ISharedVault.sol";

library SharedVaultPreviewLib {
  function previewWithdraw(
    uint256 shares,
    uint256 currentTotalSupply,
    uint256[4] memory idleBalances,
    ISharedVault.Position[] memory positions,
    address[4] memory tokens,
    ISharedConfigManager configManager,
    uint16 vaultOwnerFeeBasisPoint
  ) external view returns (uint256[4] memory amounts) {
    if (currentTotalSupply == 0) return amounts;

    uint16 platformBps = configManager.platformFeeBasisPoint();
    uint16 ownerBps = vaultOwnerFeeBasisPoint;
    if (uint256(platformBps) + uint256(ownerBps) > 10_000) {
      ownerBps = platformBps > 10_000 ? 0 : uint16(10_000 - platformBps);
    }
    uint256 combinedFeeBps = uint256(platformBps) + uint256(ownerBps);
    uint256 keepFeeBps = combinedFeeBps >= 10_000 ? 0 : 10_000 - combinedFeeBps;

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen; ) {
      ISharedVault.Position memory pos = positions[p];
      (uint256 total0, uint256 total1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);
      (uint256 principal0, uint256 principal1) = ISharedStrategy(pos.strategy).getPositionPrincipalAmounts(
        pos.nfpm,
        pos.tokenId
      );
      uint256 owed0 = total0 > principal0 ? total0 - principal0 : 0;
      uint256 owed1 = total1 > principal1 ? total1 - principal1 : 0;
      uint256 netOwed0 = keepFeeBps == 10_000 ? owed0 : FullMath.mulDiv(owed0, keepFeeBps, 10_000);
      uint256 netOwed1 = keepFeeBps == 10_000 ? owed1 : FullMath.mulDiv(owed1, keepFeeBps, 10_000);
      for (uint256 i; i < 4; ) {
        if (tokens[i] == pos.token0) idleBalances[i] += principal0 + netOwed0;
        else if (tokens[i] == pos.token1) idleBalances[i] += principal1 + netOwed1;
        unchecked {
          i++;
        }
      }
      unchecked {
        p++;
      }
    }

    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) amounts[i] = FullMath.mulDiv(shares, idleBalances[i], currentTotalSupply);
      unchecked {
        i++;
      }
    }
  }

  function previewDeposit(
    uint256[4] memory amounts,
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    address[4] memory tokens,
    ISharedConfigManager configManager,
    uint256 initialShares
  ) external view returns (uint256 shares) {
    if (currentTotalSupply == 0) {
      for (uint256 i; i < 4; ) {
        if (amounts[i] > 0) return initialShares;
        unchecked {
          i++;
        }
      }
      return 0;
    }

    shares = type(uint256).max;
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
        uint256 s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
        if (s < shares) shares = s;
      }
      unchecked {
        i++;
      }
    }
    if (shares == type(uint256).max) return 0;

    (bool valid, ) = _buildTransferAmounts(amounts, shares, currentTotalSupply, totalBalances, tokens, configManager);
    if (!valid) return 0;
  }

  /// @notice Compute the proportional transfer amounts required for a subsequent deposit.
  ///         Reverts with InvalidAmount if no binding token is found, or InvalidRatio if the
  ///         caller-supplied amounts do not satisfy the vault's current ratio.
  function subsequentDepositTransfers(
    uint256[4] memory amounts,
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    address[4] memory tokens,
    ISharedConfigManager configManager
  ) external view returns (uint256[4] memory transferAmounts) {
    uint256 sharesOut = type(uint256).max;
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
        uint256 s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
        if (s < sharesOut) sharesOut = s;
      }
      unchecked {
        i++;
      }
    }
    if (sharesOut == type(uint256).max) revert ISharedCommon.InvalidAmount();

    bool valid;
    (valid, transferAmounts) = _buildTransferAmounts(
      amounts,
      sharesOut,
      currentTotalSupply,
      totalBalances,
      tokens,
      configManager
    );
    if (!valid) revert ISharedCommon.InvalidRatio();
  }

  /// @notice Returns the minimum deposit amounts required by the current vault ratio.
  function minDepositAmounts(
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    address[4] memory tokens,
    ISharedConfigManager configManager
  ) external view returns (uint256[4] memory minAmounts) {
    if (currentTotalSupply == 0) return minAmounts;
    uint8 prec = configManager.minTokenPrecision();
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0) && totalBalances[i] > 0) {
        minAmounts[i] = _minTokenAmt(tokens[i], prec);
      }
      unchecked {
        i++;
      }
    }
  }

  function _buildTransferAmounts(
    uint256[4] memory amounts,
    uint256 sharesOut,
    uint256 currentTotalSupply,
    uint256[4] memory totalBalances,
    address[4] memory tokens,
    ISharedConfigManager configManager
  ) private view returns (bool valid, uint256[4] memory transferAmounts) {
    uint8 prec = configManager.minTokenPrecision();
    for (uint256 i; i < 4; ) {
      if (tokens[i] != address(0)) {
        if (totalBalances[i] == 0) {
          if (amounts[i] != 0) return (false, transferAmounts);
        } else {
          uint256 proportional = FullMath.mulDivRoundingUp(sharesOut, totalBalances[i], currentTotalSupply);
          uint256 minAmt = _minTokenAmt(tokens[i], prec);
          transferAmounts[i] = proportional < minAmt ? minAmt : proportional;
          if (amounts[i] < transferAmounts[i]) return (false, transferAmounts);
        }
      }
      unchecked {
        i++;
      }
    }
    valid = true;
  }

  function _minTokenAmt(address token, uint8 prec) private view returns (uint256) {
    if (prec == 0) return 0;
    uint8 dec = IERC20Metadata(token).decimals();
    return dec > prec ? 10 ** uint256(dec - prec) : 1;
  }
}
