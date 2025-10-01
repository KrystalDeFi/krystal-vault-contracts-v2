// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMasterChefV3 {
  function nonfungiblePositionManager() external view returns (address);

  function harvest(uint256 tokenId, address to) external;

  function withdraw(uint256 tokenId, address to) external;
}
