// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./Common.t.sol";
import { LpStrategyImpl } from "../contracts/strategies/lp/LpStrategyImpl.sol";
import { ICommon } from "../contracts/interfaces/ICommon.sol";
import { ILpStrategy } from "../contracts/interfaces/strategies/ILpStrategy.sol";
import { INonfungiblePositionManager as INFPM } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "forge-std/console.sol";

contract LpStrategyTest is Common {
  address public constant WETH = 0x4200000000000000000000000000000000000006;
  address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
  address public constant USER = 0x1234567890123456789012345678901234567890;
  address public constant NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

  function setUp() public {
    uint256 fork = vm.createFork("https://base.llamarpc.com", 27448360);
    vm.selectFork(fork);
  }

  function test_LpStrategy() public {
    console.log("==== test_LpStrategy ====");
    vm.startBroadcast(USER);
    setErc20Balance(WETH, USER, 100 ether);
    setErc20Balance(DAI, USER, 100000 ether);
    LpStrategyImpl lpStrategy = new LpStrategyImpl();
    lpStrategy.initialize(WETH);

    ICommon.Asset[] memory assets = new ICommon.Asset[](2);
    assets[0] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: WETH,
      tokenId: 0,
      amount: 1 ether
    });
    assets[1] = ICommon.Asset({
      assetType: ICommon.AssetType.ERC20,
      strategy: address(0),
      token: DAI,
      tokenId: 0,
      amount: 2000 ether
    });

    ILpStrategy.MintPositionParams memory mintParams = ILpStrategy.MintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: DAI,
      fee: 3000,
      tickLower: -887220,
      tickUpper: 887220,
      amount0Min: 0,
      amount1Min: 0
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.MintPosition),
      params: abi.encode(mintParams),
      abiEncodedUserOrder: new bytes(0),
      orderSignature: new bytes(0)
    });
    IERC20(WETH).transfer(address(lpStrategy), 1 ether);
    IERC20(DAI).transfer(address(lpStrategy), 2000 ether);
    ICommon.Asset[] memory returnAssets = lpStrategy.convert(assets, abi.encode(instruction));
    assertEq(returnAssets.length, 3);
    assertEq(returnAssets[0].token, WETH);
    assertEq(returnAssets[0].amount, 0 ether);
    assertEq(returnAssets[1].token, DAI);
    assertEq(returnAssets[1].amount, 77577661546568449798);
    assertEq(returnAssets[2].token, NFPM);
    assertEq(returnAssets[2].amount, 1);
    assertNotEq(returnAssets[2].tokenId, 0);
  }
}
