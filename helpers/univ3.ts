import bn from "bignumber.js";
import { BigNumberish, keccak256 } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import { pack } from "@ethersproject/solidity";

export const MaxUint128 = BigNumber.from(2).pow(128).sub(1);
export const MaxUint256 = BigNumber.from(2).pow(256).sub(1);

export const getMinTick = (tickSpacing: number) => Math.ceil(-887272 / tickSpacing) * tickSpacing;
export const getMaxTick = (tickSpacing: number) => Math.floor(887272 / tickSpacing) * tickSpacing;

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export const getMaxLiquidityPerTick = (tickSpacing: number) =>
  BigNumber.from(2)
    .pow(128)
    .sub(1)
    .div((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / tickSpacing + 1);

export const MIN_SQRT_RATIO = BigNumber.from("4295128739");
export const MAX_SQRT_RATIO = BigNumber.from("1461446703485210103287273052203988822378723970342");

export enum FeeAmount {
  LOW = 500,
  MEDIUM = 3000,
  HIGH = 10000,
}

export const TICK_SPACINGS: { [amount in FeeAmount]: number } = {
  [FeeAmount.LOW]: 10,
  [FeeAmount.MEDIUM]: 60,
  [FeeAmount.HIGH]: 200,
};

export function encodePriceSqrt(reserve1: BigNumberish, reserve0: BigNumberish): BigNumber {
  return BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString(),
  );
}

export function getPositionKey(address: string, lowerTick: number, upperTick: number): string {
  return keccak256(pack(["address", "int24", "int24"], [address, lowerTick, upperTick]));
}

export function generateTick(price: number, decimals0: number, decimals1: number) {
  // note the change of logarithmic base
  return Math.round(Math.log(price * Math.pow(10, decimals1 - decimals0)) / Math.log(1.0001));
}

export function tickToPrice(tick: number, decimals0: number, decimals1: number) {
  return tickToRawPrice(tick) / Math.pow(10, decimals1 - decimals0);
}

export function tickToRawPrice(tick: number) {
  return Math.pow(1.0001, tick);
}

export function priceBands(price: number, percent: number) {
  return [price * ((100 - percent) / 100), price * ((100 + percent) / 100)];
}

export function tickBands(tick: number, percent: number) {
  if (tick > 0) {
    return [tick * ((100 - percent) / 100), tick * ((100 + percent) / 100)];
  } else {
    return [tick * ((100 + percent) / 100), tick * ((100 - percent) / 100)];
  }
}

export function baseTicksFromCurrentTick(
  tick: number,
  decimals0: number,
  decimals1: number,
  tickSpacing: number,
  percent: number,
) {
  let lowerTick: number;
  let upperTick: number;
  [lowerTick, upperTick] = tickBands(tick, percent);
  return [roundTick(lowerTick, tickSpacing), roundTick(upperTick, tickSpacing)];
}

export function limitTicksFromCurrentTick(
  tick: number,
  decimals0: number,
  decimals1: number,
  tickSpacing: number,
  percent: number,
  above: boolean,
) {
  let price = tickToPrice(tick, decimals0, decimals1);
  let priceTick = generateTick(price, decimals0, decimals1);
  let lowerTick: number;
  let upperTick: number;
  [lowerTick, upperTick] = tickBands(tick, percent);

  let modulus = tick % tickSpacing;
  modulus = modulus < 0 ? modulus + tickSpacing : modulus;

  if (above) {
    return [tick + tickSpacing - modulus, roundTick(upperTick, tickSpacing)];
  } else {
    return [roundTick(lowerTick, tickSpacing), tick - modulus];
  }
}

export function positionTicksFromCurrentTick(
  tick: number,
  decimals0: number,
  decimals1: number,
  tickSpacing: number,
  percent: number,
  above: boolean,
) {
  let [baseLower, baseUpper] = baseTicksFromCurrentTick(tick, decimals0, decimals1, tickSpacing, percent);
  let [limitLower, limitUpper] = limitTicksFromCurrentTick(tick, decimals0, decimals1, tickSpacing, percent, above);
  return [baseLower, baseUpper, limitLower, limitUpper];
}

export function roundTick(tick: number, tickSpacing: number) {
  let modulus = tick % tickSpacing;
  modulus = modulus < 0 ? modulus + tickSpacing : modulus;
  return modulus > tickSpacing / 2 ? tick - modulus : tick + tickSpacing - modulus;
}
