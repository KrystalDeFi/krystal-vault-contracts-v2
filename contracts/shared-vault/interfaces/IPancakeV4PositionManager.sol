// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { PancakeV4PoolKey } from "./ISharedPancakeV4Utils.sol";

type PancakeV4PositionInfo is uint256;

library PancakeV4PositionInfoLibrary {
  uint8 internal constant TICK_LOWER_OFFSET = 8;
  uint8 internal constant TICK_UPPER_OFFSET = 32;

  function tickLower(PancakeV4PositionInfo info) internal pure returns (int24 tick) {
    uint256 raw = PancakeV4PositionInfo.unwrap(info);
    assembly ("memory-safe") {
      tick := signextend(2, shr(TICK_LOWER_OFFSET, raw))
    }
  }

  function tickUpper(PancakeV4PositionInfo info) internal pure returns (int24 tick) {
    uint256 raw = PancakeV4PositionInfo.unwrap(info);
    assembly ("memory-safe") {
      tick := signextend(2, shr(TICK_UPPER_OFFSET, raw))
    }
  }
}

library PancakeV4PoolKeyLibrary {
  function toId(PancakeV4PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly ("memory-safe") {
      poolId := keccak256(poolKey, 0xc0)
    }
  }
}

struct PancakeV4TickInfo {
  uint128 liquidityGross;
  int128 liquidityNet;
  uint256 feeGrowthOutside0X128;
  uint256 feeGrowthOutside1X128;
}

interface IPancakeV4CLPoolManager {
  function initialize(PancakeV4PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24 tick);
  function getSlot0(bytes32 id)
    external
    view
    returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
  function getFeeGrowthGlobals(bytes32 id)
    external
    view
    returns (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128);
  function getPoolTickInfo(bytes32 id, int24 tick) external view returns (PancakeV4TickInfo memory);
}

interface IPancakeV4PositionManager {
  function clPoolManager() external view returns (address);
  function permit2() external view returns (address);
  function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
  function nextTokenId() external view returns (uint256);
  function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
  function getPoolAndPositionInfo(uint256 tokenId)
    external
    view
    returns (PancakeV4PoolKey memory poolKey, PancakeV4PositionInfo info);
  function positions(uint256 tokenId)
    external
    view
    returns (
      PancakeV4PoolKey memory poolKey,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      address subscriber
    );
}
