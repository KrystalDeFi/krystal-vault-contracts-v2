// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IStrategy } from "../../contracts/public-vault/interfaces/strategies/IStrategy.sol";
import { IAerodromeLpStrategy } from
  "../../contracts/public-vault/interfaces/strategies/aerodrome/IAerodromeLpStrategy.sol";
import { IFarmingStrategy } from "../../contracts/public-vault/interfaces/strategies/aerodrome/IFarmingStrategy.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";
import "forge-std/console.sol";

contract Debug is Test {
  function test() public {
    bytes memory data = bytes(
      hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000020000000000000000000000000827922686190790b37229fd06084350e74485b7200000000000000000000000020fbd133897ef802e0235db77bb19a071e257d41000000000000000000000000420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000c8fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffded88fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdf170000000000000000000000000000000000000000000000016fdff6e27c73cef8000000000000000000000000000000000000000000000000000017bfdbba7878a00000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000"
    );
    ICommon.Instruction memory ins = abi.decode(data, (ICommon.Instruction));
    console.log("type");
    console.log(ins.instructionType);
    console.log("params");
    console.logBytes(ins.params);
    // IAerodromeLpStrategy.SwapAndMintPositionParams memory params = abi.decode(
    //   ins.params, (IAerodromeLpStrategy.SwapAndMintPositionParams)
    // );
    IAerodromeLpStrategy.SwapAndMintPositionParams memory params = IAerodromeLpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(0x827922686190790b37229fd06084350E74485b72),
      token0: 0x20FbD133897Ef802e0235dB77bB19a071E257d41,
      token1: 0x4200000000000000000000000000000000000006,
      tickSpacing: 200,
      tickLower: int24(int256(uint256(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffded88))),
      tickUpper: int24(int256(uint256(0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdf170))),
      amount0Min: 0x000000000000000000000000000000000000000000000016fdff6e27c73cef80,
      amount1Min: 0x00000000000000000000000000000000000000000000000000017bfdbba7878a,
      swapData: ""
    });
    console.log("params2");
    console.logBytes(abi.encode(params));
    console.log("params3");
    console.logBytes(
      abi.encode(
        ICommon.Instruction({
          instructionType: uint8(IFarmingStrategy.FarmingInstructionType.CreateAndDepositLP),
          params: abi.encode(params)
        })
      )
    );
  }
}
