export const mockOrder = {
  types: {
    AutoCompoundAction: [
      {
        name: "maxGasProportionX64",
        type: "int256",
      },
      {
        name: "poolSlippageX64",
        type: "int256",
      },
      {
        name: "swapSlippageX64",
        type: "int256",
      },
    ],
    AutoCompoundCondition: [
      {
        name: "type",
        type: "string",
      },
      {
        name: "feeBasedCondition",
        type: "FeeBasedCondition",
      },
      {
        name: "timeBasedCondition",
        type: "TimeBasedCondition",
      },
    ],
    AutoCompoundConfig: [
      {
        name: "condition",
        type: "AutoCompoundCondition",
      },
      {
        name: "action",
        type: "AutoCompoundAction",
      },
    ],
    AutoExitAction: [
      {
        name: "maxGasProportionX64",
        type: "int256",
      },
      {
        name: "swapSlippageX64",
        type: "int256",
      },
      {
        name: "liquiditySlippageX64",
        type: "int256",
      },
      {
        name: "tokenOutAddress",
        type: "address",
      },
    ],
    AutoExitConfig: [
      {
        name: "condition",
        type: "Condition",
      },
      {
        name: "action",
        type: "AutoExitAction",
      },
    ],
    Condition: [
      {
        name: "type",
        type: "string",
      },
      {
        name: "sqrtPriceX96",
        type: "int160",
      },
      {
        name: "timeBuffer",
        type: "int64",
      },
      {
        name: "tickOffsetCondition",
        type: "TickOffsetCondition",
      },
      {
        name: "priceOffsetCondition",
        type: "PriceOffsetCondition",
      },
      {
        name: "tokenRatioCondition",
        type: "TokenRatioCondition",
      },
    ],
    FeeBasedCondition: [
      {
        name: "minFeeEarnedUsdX64",
        type: "int256",
      },
    ],
    Order: [
      {
        name: "chainId",
        type: "int64",
      },
      {
        name: "nfpmAddress",
        type: "address",
      },
      {
        name: "tokenId",
        type: "uint256",
      },
      {
        name: "orderType",
        type: "string",
      },
      {
        name: "config",
        type: "OrderConfig",
      },
      {
        name: "signatureTime",
        type: "int64",
      },
    ],
    OrderConfig: [
      {
        name: "rebalanceConfig",
        type: "RebalanceConfig",
      },
      {
        name: "rangeOrderConfig",
        type: "RangeOrderConfig",
      },
      {
        name: "autoCompoundConfig",
        type: "AutoCompoundConfig",
      },
      {
        name: "autoExitConfig",
        type: "AutoExitConfig",
      },
    ],
    PriceOffsetAction: [
      {
        name: "baseToken",
        type: "uint32",
      },
      {
        name: "lowerOffsetSqrtPriceX96",
        type: "int160",
      },
      {
        name: "upperOffsetSqrtPriceX96",
        type: "int160",
      },
    ],
    PriceOffsetCondition: [
      {
        name: "baseToken",
        type: "uint32",
      },
      {
        name: "gteOffsetSqrtPriceX96",
        type: "uint256",
      },
      {
        name: "lteOffsetSqrtPriceX96",
        type: "uint256",
      },
    ],
    RangeOrderAction: [
      {
        name: "maxGasProportionX64",
        type: "int256",
      },
      {
        name: "swapSlippageX64",
        type: "int256",
      },
      {
        name: "withdrawSlippageX64",
        type: "int256",
      },
    ],
    RangeOrderCondition: [
      {
        name: "zeroToOne",
        type: "bool",
      },
      {
        name: "gteTickAbsolute",
        type: "int32",
      },
      {
        name: "lteTickAbsolute",
        type: "int32",
      },
    ],
    RangeOrderConfig: [
      {
        name: "condition",
        type: "RangeOrderCondition",
      },
      {
        name: "action",
        type: "RangeOrderAction",
      },
    ],
    RebalanceAction: [
      {
        name: "maxGasProportionX64",
        type: "int256",
      },
      {
        name: "swapSlippageX64",
        type: "int256",
      },
      {
        name: "liquiditySlippageX64",
        type: "int256",
      },
      {
        name: "type",
        type: "string",
      },
      {
        name: "tickOffsetAction",
        type: "TickOffsetAction",
      },
      {
        name: "priceOffsetAction",
        type: "PriceOffsetAction",
      },
      {
        name: "tokenRatioAction",
        type: "TokenRatioAction",
      },
    ],
    RebalanceAutoCompound: [
      {
        name: "action",
        type: "RebalanceAutoCompoundAction",
      },
    ],
    RebalanceAutoCompoundAction: [
      {
        name: "maxGasProportionX64",
        type: "int256",
      },
      {
        name: "feeToPrincipalRatioThresholdX64",
        type: "int256",
      },
    ],
    RebalanceConfig: [
      {
        name: "rebalanceCondition",
        type: "Condition",
      },
      {
        name: "rebalanceAction",
        type: "RebalanceAction",
      },
      {
        name: "autoCompound",
        type: "RebalanceAutoCompound",
      },
      {
        name: "recurring",
        type: "bool",
      },
    ],
    TickOffsetAction: [
      {
        name: "tickLowerOffset",
        type: "uint32",
      },
      {
        name: "tickUpperOffset",
        type: "uint32",
      },
    ],
    TickOffsetCondition: [
      {
        name: "gteTickOffset",
        type: "uint32",
      },
      {
        name: "lteTickOffset",
        type: "uint32",
      },
    ],
    TimeBasedCondition: [
      {
        name: "intervalInSecond",
        type: "int256",
      },
    ],
    TokenRatioAction: [
      {
        name: "tickWidth",
        type: "uint32",
      },
      {
        name: "token0RatioX64",
        type: "int256",
      },
    ],
    TokenRatioCondition: [
      {
        name: "lteToken0RatioX64",
        type: "int256",
      },
      {
        name: "gteToken0RatioX64",
        type: "int256",
      },
    ],
  },
  primaryType: "Order",
  message: {
    chainId: "8453",
    nfpmAddress: "0xa51adb08cbe6ae398046a23bec013979816b77ab",
    tokenId: "1878",
    orderType: "ORDER_TYPE_AUTO_EXIT",
    config: {
      autoCompoundConfig: {
        action: {
          maxGasProportionX64: "0",
          poolSlippageX64: "0",
          swapSlippageX64: "0",
        },
        condition: {
          feeBasedCondition: {
            minFeeEarnedUsdX64: "0",
          },
          timeBasedCondition: {
            intervalInSecond: "0",
          },
          type: "",
          _type: "",
        },
      },
      autoExitConfig: {
        action: {
          liquiditySlippageX64: "184467440737095520",
          maxGasProportionX64: "16917025071065509888",
          swapSlippageX64: "184467440737095520",
          tokenOutAddress: "0x0000000000000000000000000000000000000000",
        },
        condition: {
          priceOffsetCondition: {
            baseToken: "0",
            gteOffsetSqrtPriceX96: "0",
            lteOffsetSqrtPriceX96: "0",
          },
          sqrtPriceX96: "79213676885104809576267151027",
          tickOffsetCondition: {
            gteTickOffset: "1823",
            lteTickOffset: "2232",
          },
          timeBuffer: "3600",
          tokenRatioCondition: {
            gteToken0RatioX64: "0",
            lteToken0RatioX64: "0",
          },
          type: "CONDITION_TYPE_PERCENTAGE",
          _type: "CONDITION_TYPE_PERCENTAGE",
        },
      },
      rangeOrderConfig: {
        action: {
          maxGasProportionX64: "0",
          swapSlippageX64: "0",
          withdrawSlippageX64: "0",
        },
        condition: {
          gteTickAbsolute: "0",
          lteTickAbsolute: "0",
          zeroToOne: false,
        },
      },
      rebalanceConfig: {
        autoCompound: {
          action: {
            feeToPrincipalRatioThresholdX64: "0",
            maxGasProportionX64: "0",
          },
        },
        rebalanceAction: {
          liquiditySlippageX64: "0",
          maxGasProportionX64: "0",
          priceOffsetAction: {
            baseToken: "0",
            lowerOffsetSqrtPriceX96: "0",
            upperOffsetSqrtPriceX96: "0",
          },
          swapSlippageX64: "0",
          tickOffsetAction: {
            tickLowerOffset: "0",
            tickUpperOffset: "0",
          },
          tokenRatioAction: {
            tickWidth: "0",
            token0RatioX64: "0",
          },
          type: "",
          _type: "",
        },
        rebalanceCondition: {
          priceOffsetCondition: {
            baseToken: "0",
            gteOffsetSqrtPriceX96: "0",
            lteOffsetSqrtPriceX96: "0",
          },
          sqrtPriceX96: "0",
          tickOffsetCondition: {
            gteTickOffset: "0",
            lteTickOffset: "0",
          },
          timeBuffer: "0",
          tokenRatioCondition: {
            gteToken0RatioX64: "0",
            lteToken0RatioX64: "0",
          },
          type: "",
          _type: "",
        },
        recurring: false,
      },
    },
    signatureTime: "1739948009",
  },
};
