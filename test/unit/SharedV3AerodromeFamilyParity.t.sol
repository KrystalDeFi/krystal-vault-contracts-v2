// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Cross-family parity, NFT-position-manager families: the StrategyFamilyParityBase properties run against
// SharedV3Strategy and SharedAerodromeStrategy (forks: keep both suites mirrored) over faithful Uniswap V3 /
// Slipstream mocks (test/helpers/FaithfulV3Mocks.sol). Twin of SharedV4PancakeFamilyParity.t.sol.

import {
  INonfungiblePositionManager as INFPM
} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import {
  INonfungiblePositionManager as IAeroNfpm
} from "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";

import { StrategyFamilyParityBase } from "../helpers/StrategyFamilyParity.sol";
import {
  FaithfulClPoolCore,
  FaithfulNfpmCore,
  FaithfulUniV3Pool,
  FaithfulUniV3Factory,
  FaithfulUniV3Nfpm,
  FaithfulSlipstreamPool,
  FaithfulSlipstreamFactory,
  FaithfulSlipstreamNfpm
} from "../helpers/FaithfulV3Mocks.sol";

/// @dev Adapter shared by the two NFPM families: V3Utils-style payloads, the NFPM ledger and the pool's custody.
abstract contract NfpmFamilyParity is StrategyFamilyParityBase {
  FaithfulClPoolCore internal pool;

  /// @dev The strategy's `OperationType` prefixes for EXECUTE_INSTRUCTIONS and SWAP_AND_INCREASE.
  function _instructionsOp() internal pure virtual returns (bytes memory);

  function _increaseOp() internal pure virtual returns (bytes memory);

  function _liquidityOf(uint256 id) internal view override returns (uint128) {
    return FaithfulNfpmCore(nfpm).positionLiquidity(id);
  }

  function _uncollectedFees(uint256 id) internal view override returns (uint256, uint256) {
    return FaithfulNfpmCore(nfpm).collectable(id);
  }

  function _accrueFees(uint256 fee0, uint256 fee1) internal override {
    _fund(address(this), token0, fee0);
    _fund(address(this), token1, fee1);
    token0.approve(address(pool), fee0);
    token1.approve(address(pool), fee1);
    pool.accrueSwapFees(fee0, fee1);
  }

  function _custody() internal view override returns (address) {
    return address(pool);
  }

  function _assertNoApprovalsLeft() internal view override {
    assertEq(token0.allowance(address(vault), nfpm), 0, "no token0 allowance left to the NFPM");
    assertEq(token1.allowance(address(vault), nfpm), 0, "no token1 allowance left to the NFPM");
  }

  function _compoundData(uint256 id) internal view override returns (bytes memory) {
    return bytes.concat(_instructionsOp(), abi.encode(nfpm, id, _instructions(IV3Utils.WhatToDo.COMPOUND_FEES, 0)));
  }

  function _decreaseData(uint256 id, uint128 liquidity) internal view override returns (bytes memory) {
    return bytes.concat(
      _instructionsOp(), abi.encode(nfpm, id, _instructions(IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP, liquidity))
    );
  }

  function _increaseData(uint256 id, uint256 amount0, uint256 amount1) internal view override returns (bytes memory) {
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: nfpm,
      tokenId: id,
      amount0: amount0,
      amount1: amount1,
      amount2: 0,
      recipient: address(vault),
      deadline: block.timestamp,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });
    return bytes.concat(_increaseOp(), abi.encode(params, new address[](0), new uint256[](0), uint256(0)));
  }

  /// @dev No target token (no swap), no minimums, no gas fee.
  function _instructions(IV3Utils.WhatToDo whatToDo, uint128 liquidity)
    internal
    view
    returns (IV3Utils.Instructions memory)
  {
    return IV3Utils.Instructions({
      whatToDo: whatToDo,
      protocol: 0,
      targetToken: address(0),
      amountRemoveMin0: 0,
      amountRemoveMin1: 0,
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      tickLower: 0,
      tickUpper: 0,
      compoundFees: false,
      liquidity: liquidity,
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
  }
}

/// @dev Uniswap V3 family.
contract SharedV3FamilyParityTest is NfpmFamilyParity {
  function _deployFamily() internal override returns (address, address) {
    FaithfulUniV3Pool uniPool = new FaithfulUniV3Pool(address(token0), address(token1), 500, 10, SQRT_PRICE_1_1);
    pool = uniPool;
    FaithfulUniV3Nfpm uniNfpm = new FaithfulUniV3Nfpm(uniPool, new FaithfulUniV3Factory(uniPool));
    return (address(uniNfpm), address(new SharedV3Strategy(SWAP_ROUTER)));
  }

  function _mintPosition(address owner, uint256 amount0, uint256 amount1) internal override returns (uint256 id) {
    _fund(owner, token0, amount0);
    _fund(owner, token1, amount1);
    vm.startPrank(owner);
    token0.approve(nfpm, amount0);
    token1.approve(nfpm, amount1);
    (id,,,) = FaithfulUniV3Nfpm(nfpm)
      .mint(
        INFPM.MintParams({
        token0: address(token0),
        token1: address(token1),
        fee: 500,
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: owner,
        deadline: block.timestamp
      })
      );
    vm.stopPrank();
  }

  function _instructionsOp() internal pure override returns (bytes memory) {
    return abi.encode(SharedV3Strategy.OperationType.EXECUTE_INSTRUCTIONS);
  }

  function _increaseOp() internal pure override returns (bytes memory) {
    return abi.encode(SharedV3Strategy.OperationType.SWAP_AND_INCREASE);
  }
}

/// @dev Aerodrome Slipstream family (fork of the V3 strategy; keep mirrored with SharedV3FamilyParityTest).
contract SharedAerodromeFamilyParityTest is NfpmFamilyParity {
  function _deployFamily() internal override returns (address, address) {
    FaithfulSlipstreamPool clPool = new FaithfulSlipstreamPool(address(token0), address(token1), 10, SQRT_PRICE_1_1);
    pool = clPool;
    FaithfulSlipstreamNfpm clNfpm = new FaithfulSlipstreamNfpm(clPool, new FaithfulSlipstreamFactory(clPool));
    return (address(clNfpm), address(new SharedAerodromeStrategy(SWAP_ROUTER)));
  }

  function _mintPosition(address owner, uint256 amount0, uint256 amount1) internal override returns (uint256 id) {
    _fund(owner, token0, amount0);
    _fund(owner, token1, amount1);
    vm.startPrank(owner);
    token0.approve(nfpm, amount0);
    token1.approve(nfpm, amount1);
    (id,,,) = FaithfulSlipstreamNfpm(nfpm)
      .mint(
        IAeroNfpm.MintParams({
        token0: address(token0),
        token1: address(token1),
        tickSpacing: 10,
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: owner,
        deadline: block.timestamp,
        sqrtPriceX96: 0
      })
      );
    vm.stopPrank();
  }

  function _instructionsOp() internal pure override returns (bytes memory) {
    return abi.encode(SharedAerodromeStrategy.OperationType.EXECUTE_INSTRUCTIONS);
  }

  function _increaseOp() internal pure override returns (bytes memory) {
    return abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_INCREASE);
  }
}
