// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

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
    // Clamp the owner bps so platform + owner never exceeds 100%, matching
    // SharedStrategyFeeConfig.performanceFeeConfig (the FeeConfig the real collect path uses).
    if (uint256(platformBps) + uint256(ownerBps) > 10_000) {
      ownerBps = uint16(10_000 - platformBps);
    }
    bool netFees = platformBps > 0 || ownerBps > 0;

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen;) {
      ISharedVault.Position memory pos = positions[p];
      uint256 amount0;
      uint256 amount1;
      if (netFees) {
        (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
          ISharedStrategy(pos.strategy).getPositionAmountsSplit(pos.nfpm, pos.tokenId);
        uint256 owed0 = total0 > principal0 ? total0 - principal0 : 0;
        uint256 owed1 = total1 > principal1 ? total1 - principal1 : 0;
        amount0 = principal0 + netAfterPerformanceFees(owed0, platformBps, ownerBps);
        amount1 = principal1 + netAfterPerformanceFees(owed1, platformBps, ownerBps);
      } else {
        (amount0, amount1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);
      }
      for (uint256 i; i < 4;) {
        if (tokens[i] == pos.token0) idleBalances[i] += amount0;
        else if (tokens[i] == pos.token1) idleBalances[i] += amount1;
        unchecked {
          i++;
        }
      }
      unchecked {
        p++;
      }
    }

    for (uint256 i; i < 4;) {
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
      for (uint256 i; i < 4;) {
        if (amounts[i] > 0) return initialShares;
        unchecked {
          i++;
        }
      }
      return 0;
    }

    shares = type(uint256).max;
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0) && totalBalances[i] > 0 && amounts[i] > 0) {
        uint256 s = FullMath.mulDiv(amounts[i], currentTotalSupply, totalBalances[i]);
        if (s < shares) shares = s;
      }
      unchecked {
        i++;
      }
    }
    if (shares == type(uint256).max) return 0;

    (bool valid,) = _buildTransferAmounts(amounts, shares, currentTotalSupply, totalBalances, tokens, configManager);
    if (!valid) return 0;
  }

  function computeTotalBalances(
    uint256[4] memory idleBalances,
    ISharedVault.Position[] memory positions,
    address[4] memory tokens,
    ISharedConfigManager configManager,
    uint16 vaultOwnerFeeBasisPoint
  ) external view returns (uint256[4] memory balances) {
    balances = idleBalances;
    (uint16 platformBps, uint16 ownerBps) = _performanceFeeBps(configManager, vaultOwnerFeeBasisPoint);
    bool netFees = platformBps > 0 || ownerBps > 0;

    uint256 posLen = positions.length;
    for (uint256 p; p < posLen;) {
      ISharedVault.Position memory pos = positions[p];

      uint256 amount0;
      uint256 amount1;
      if (netFees) {
        (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
          ISharedStrategy(pos.strategy).getPositionAmountsSplit(pos.nfpm, pos.tokenId);
        amount0 = _netPositionAmount(total0, principal0, platformBps, ownerBps);
        amount1 = _netPositionAmount(total1, principal1, platformBps, ownerBps);
      } else {
        (amount0, amount1) = ISharedStrategy(pos.strategy).getPositionAmounts(pos.nfpm, pos.tokenId);
      }

      for (uint256 i; i < 4;) {
        if (tokens[i] == pos.token0) balances[i] += amount0;
        else if (tokens[i] == pos.token1) balances[i] += amount1;
        unchecked {
          i++;
        }
      }
      unchecked {
        p++;
      }
    }
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
    for (uint256 i; i < 4;) {
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
    (valid, transferAmounts) =
      _buildTransferAmounts(amounts, sharesOut, currentTotalSupply, totalBalances, tokens, configManager);
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
    for (uint256 i; i < 4;) {
      if (tokens[i] != address(0) && totalBalances[i] > 0) minAmounts[i] = _minTokenAmt(tokens[i], prec);
      unchecked {
        i++;
      }
    }
  }

  /// @notice Validation for tracking a new LP position, hosted here (moved out of SharedVault)
  ///         purely to keep SharedVault under the EIP-170 deploy-size limit.
  /// @dev Delegatecalled from SharedVault, so `address(this)` is the vault. Reverts (bubbling the
  ///      same custom errors, in the same order, SharedVault used inline) when the position must
  ///      not be tracked:
  ///      - `probeStrategy`: probe `getPositionAmounts` to confirm the target can value the
  ///        position before it is tracked (CALL_WITH_POSITIONS targets only).
  ///      - Canonical token pair via `getPositionTokens`: a buggy target can report any vault-token
  ///        pair but `_getTotalBalances()` would attribute LP value to the wrong assets,
  ///        mispricing shares.
  ///      - `vaultTokens`: the vault's own `isVaultToken[token0] && isVaultToken[token1]` verdict,
  ///        passed in (this library cannot read vault storage) so the check keeps its original
  ///        position before the ownership probe.
  ///      - NFT ownership: an unowned position would misprice shares.
  function validatePositionAdd(
    address strategy,
    address nfpm,
    uint256 tokenId,
    address token0,
    address token1,
    bool probeStrategy,
    bool vaultTokens
  ) external view {
    if (probeStrategy) {
      (bool ok, bytes memory probeData) =
        strategy.staticcall(abi.encodeCall(ISharedStrategy.getPositionAmounts, (nfpm, tokenId)));
      require(ok && probeData.length >= 64, ISharedCommon.InvalidTarget(strategy));
    }
    (bool tokensOk, bytes memory tokensData) =
      strategy.staticcall(abi.encodeCall(ISharedStrategy.getPositionTokens, (nfpm, tokenId)));
    require(tokensOk && tokensData.length >= 64, ISharedCommon.InvalidTarget(strategy));
    (address canonToken0, address canonToken1) = abi.decode(tokensData, (address, address));
    require(canonToken0 == token0 && canonToken1 == token1, ISharedCommon.TokenNotConfigured());
    require(vaultTokens, ISharedCommon.TokenNotConfigured());
    (bool ownsNft, bytes memory ownerData) = nfpm.staticcall(abi.encodeCall(IERC721.ownerOf, (tokenId)));
    require(
      ownsNft && ownerData.length >= 32 && abi.decode(ownerData, (address)) == address(this),
      ISharedCommon.InvalidOperation()
    );
  }

  /// @notice Before untracking a position, verify it is truly exited. If the vault still holds the
  ///         NFT, require the strategy reports zero amounts — a non-zero value means a live LP
  ///         position would be untracked, understating TVL and enabling mispriced
  ///         deposits/withdrawals.
  /// @dev Delegatecalled from SharedVault (`address(this)` is the vault); hosted here to keep
  ///      SharedVault under the EIP-170 deploy-size limit.
  function verifyPositionExit(address strategy, address nfpm, uint256 tokenId) external view {
    (bool callOk, bytes memory ownerData) = nfpm.staticcall(abi.encodeCall(IERC721.ownerOf, (tokenId)));
    if (callOk && ownerData.length >= 32 && abi.decode(ownerData, (address)) == address(this)) {
      (bool amtsOk, bytes memory amtsData) =
        strategy.staticcall(abi.encodeCall(ISharedStrategy.getPositionAmounts, (nfpm, tokenId)));
      require(amtsOk && amtsData.length >= 64, ISharedCommon.InvalidOperation());
      (uint256 a0, uint256 a1) = abi.decode(amtsData, (uint256, uint256));
      require(a0 == 0 && a1 == 0, ISharedCommon.InvalidOperation());
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
    for (uint256 i; i < 4;) {
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

  /// @dev Net LP-fee amount retained by shareholders after platform + owner performance fees.
  ///      Mirrors `SharedStrategyFees.applyFees` EXACTLY so the per-position FEE term matches the on-chain
  ///      collect to the wei: each fee is computed from the ORIGINAL `owed` amount with floor division
  ///      (NOT from a running remainder) and applied SEQUENTIALLY (platform first, then owner), each
  ///      clamped to the remaining balance. Withdraw exits never charge the gas fee, so it is omitted. A
  ///      single combined-bps division (`owed * (10000 - platform - owner) / 10000`) rounds differently
  ///      and under-reports the net by up to 1 wei per token per position. NOTE (W-7): matching the fee
  ///      math makes the fee TERM exact, but `previewWithdraw` as a whole remains a close UPPER-BOUND
  ///      estimate, not wei-exact — see its NatSpec for the residual per-component rounding.
  function netAfterPerformanceFees(uint256 owed, uint16 platformBps, uint16 ownerBps) internal pure returns (uint256) {
    if (owed == 0) return 0;
    uint256 platformFee = FullMath.mulDiv(owed, platformBps, 10_000);
    // platformBps <= 10_000 (config-enforced) => platformFee <= owed, so this cannot underflow.
    uint256 remaining = owed - platformFee;
    uint256 ownerFee = FullMath.mulDiv(owed, ownerBps, 10_000);
    if (ownerFee > remaining) ownerFee = remaining;
    return owed - platformFee - ownerFee;
  }

  function _performanceFeeBps(
    ISharedConfigManager configManager,
    uint16 vaultOwnerFeeBasisPoint
  ) private view returns (uint16 platformBps, uint16 ownerBps) {
    platformBps = configManager.platformFeeBasisPoint();
    ownerBps = vaultOwnerFeeBasisPoint;
    if (uint256(platformBps) + uint256(ownerBps) > 10_000) {
      ownerBps = uint16(10_000 - platformBps);
    }
  }

  function _netPositionAmount(uint256 total, uint256 principal, uint16 platformBps, uint16 ownerBps)
    private
    pure
    returns (uint256)
  {
    uint256 owed = total > principal ? total - principal : 0;
    return principal + netAfterPerformanceFees(owed, platformBps, ownerBps);
  }

  function _minTokenAmt(address token, uint8 prec) private view returns (uint256) {
    if (prec == 0) return 0;
    uint8 dec = IERC20Metadata(token).decimals();
    return dec > prec ? 10 ** uint256(dec - prec) : 1;
  }
}
