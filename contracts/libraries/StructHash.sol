// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;
pragma abicoder v2;

library StructHash {
  function _hash(bytes memory abiEncodedUserOrder) internal pure returns (bytes32) {
    return _hash(abi.decode(abiEncodedUserOrder, (Order)));
  }

  // keccak256(
  //     "RebalanceAutoCompound(RebalanceAutoCompoundAction action)RebalanceAutoCompoundAction(int256 maxGasProportionX64,int256 feeToPrincipalRatioThresholdX64)"
  // );
  bytes32 constant RebalanceAutoCompound_TYPEHASH = 0x35d8f787f18def78c8e6fcafa2acf783916baed9dc692c38b4e8a97c853b7477;
  struct RebalanceAutoCompound {
    RebalanceAutoCompoundAction action;
  }
  function _hash(RebalanceAutoCompound memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(RebalanceAutoCompound_TYPEHASH, _hash(obj.action)));
  }

  // keccak256(
  //     "RebalanceAutoCompoundAction(int256 maxGasProportionX64,int256 feeToPrincipalRatioThresholdX64)"
  // );
  bytes32 constant RebalanceAutoCompoundAction_TYPEHASH =
    0x3fa522c715dd2d3373663b38d551ef7f7a5beec25a19992cd26eae7d7df39486;
  struct RebalanceAutoCompoundAction {
    int256 maxGasProportionX64;
    int256 feeToPrincipalRatioThresholdX64;
  }
  function _hash(RebalanceAutoCompoundAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(RebalanceAutoCompoundAction_TYPEHASH, obj.maxGasProportionX64, obj.feeToPrincipalRatioThresholdX64)
      );
  }

  // keccak256(
  //     "TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)"
  // );
  bytes32 constant TickOffsetCondition_TYPEHASH = 0x62a0ad438254a5fc08168ddf3cb49a0b3c0e730e76f4fa785b4df532bc2dafb9;
  struct TickOffsetCondition {
    uint32 gteTickOffset;
    uint32 lteTickOffset;
  }
  function _hash(TickOffsetCondition memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(TickOffsetCondition_TYPEHASH, obj.gteTickOffset, obj.lteTickOffset));
  }

  // keccak256(
  //     "PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)"
  // );
  bytes32 constant PriceOffsetCondition_TYPEHASH = 0xee7cf2600f91b8ddafa790dd184ce3c665f9dc116423525b336e1edac8e07e12;
  struct PriceOffsetCondition {
    uint32 baseToken;
    uint256 gteOffsetSqrtPriceX96;
    uint256 lteOffsetSqrtPriceX96;
  }
  function _hash(PriceOffsetCondition memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(PriceOffsetCondition_TYPEHASH, obj.baseToken, obj.gteOffsetSqrtPriceX96, obj.lteOffsetSqrtPriceX96)
      );
  }

  // keccak256(
  //     "TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant TokenRatioCondition_TYPEHASH = 0x45ae7b1ead003f850829121834fe562edded567cc66a42e8315561c98a7735f9;
  struct TokenRatioCondition {
    int256 lteToken0RatioX64;
    int256 gteToken0RatioX64;
  }
  function _hash(TokenRatioCondition memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(TokenRatioCondition_TYPEHASH, obj.lteToken0RatioX64, obj.gteToken0RatioX64));
  }

  // keccak256(
  //     "Condition(string type,int160 sqrtPriceX96,int64 timeBuffer,TickOffsetCondition tickOffsetCondition,PriceOffsetCondition priceOffsetCondition,TokenRatioCondition tokenRatioCondition)PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant Condition_TYPEHASH = 0xaf36b8bda8212b5328e48351dce631ba51b3a66e23916e5bb6bbd603d2d06f08;
  struct Condition {
    string _type;
    int160 sqrtPriceX96;
    int64 timeBuffer;
    TickOffsetCondition tickOffsetCondition;
    PriceOffsetCondition priceOffsetCondition;
    TokenRatioCondition tokenRatioCondition;
  }
  function _hash(Condition memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          Condition_TYPEHASH,
          keccak256(bytes(obj._type)),
          obj.sqrtPriceX96,
          obj.timeBuffer,
          _hash(obj.tickOffsetCondition),
          _hash(obj.priceOffsetCondition),
          _hash(obj.tokenRatioCondition)
        )
      );
  }

  // keccak256(
  //     "TickOffsetAction(uint32 tickLowerOffset,uint32 tickUpperOffset)"
  // );
  bytes32 constant TickOffsetAction_TYPEHASH = 0xf5f25bd65589108507b815014b323a5f159027eba9a477039a198a5f7fc368fc;
  struct TickOffsetAction {
    uint32 tickLowerOffset;
    uint32 tickUpperOffset;
  }
  function _hash(TickOffsetAction memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(TickOffsetAction_TYPEHASH, obj.tickLowerOffset, obj.tickUpperOffset));
  }

  // keccak256(
  //     "PriceOffsetAction(uint32 baseToken,int160 lowerOffsetSqrtPriceX96,int160 upperOffsetSqrtPriceX96)"
  // );
  bytes32 constant PriceOffsetAction_TYPEHASH = 0x0a6de33fb4ce9e036ea5aa72e73288d926400e8cc438f63c7c1c84b392c5801c;
  struct PriceOffsetAction {
    uint32 baseToken;
    int160 lowerOffsetSqrtPriceX96;
    int160 upperOffsetSqrtPriceX96;
  }
  function _hash(PriceOffsetAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(PriceOffsetAction_TYPEHASH, obj.baseToken, obj.lowerOffsetSqrtPriceX96, obj.upperOffsetSqrtPriceX96)
      );
  }

  // keccak256(
  //     "TokenRatioAction(uint32 tickWidth,int256 token0RatioX64)"
  // );
  bytes32 constant TokenRatioAction_TYPEHASH = 0x2d91584261cab64f66268846e106be0b9e325f19b0457d3be9790bff2e4d9259;
  struct TokenRatioAction {
    uint32 tickWidth;
    int256 token0RatioX64;
  }
  function _hash(TokenRatioAction memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(TokenRatioAction_TYPEHASH, obj.tickWidth, obj.token0RatioX64));
  }

  // keccak256(
  //     "RebalanceAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,string type,TickOffsetAction tickOffsetAction,PriceOffsetAction priceOffsetAction,TokenRatioAction tokenRatioAction)PriceOffsetAction(uint32 baseToken,int160 lowerOffsetSqrtPriceX96,int160 upperOffsetSqrtPriceX96)TickOffsetAction(uint32 tickLowerOffset,uint32 tickUpperOffset)TokenRatioAction(uint32 tickWidth,int256 token0RatioX64)"
  // );
  bytes32 constant RebalanceAction_TYPEHASH = 0xe862ada4db7ad1d390d5445cf9eae9093553a68a1c33bdc043a9b9868c555579;
  struct RebalanceAction {
    int256 maxGasProportionX64;
    int256 swapSlippageX64;
    int256 liquiditySlippageX64;
    string _type;
    TickOffsetAction tickOffsetAction;
    PriceOffsetAction priceOffsetAction;
    TokenRatioAction tokenRatioAction;
  }
  function _hash(RebalanceAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          RebalanceAction_TYPEHASH,
          obj.maxGasProportionX64,
          obj.swapSlippageX64,
          obj.liquiditySlippageX64,
          keccak256(bytes(obj._type)),
          _hash(obj.tickOffsetAction),
          _hash(obj.priceOffsetAction),
          _hash(obj.tokenRatioAction)
        )
      );
  }

  // keccak256(
  //     "RebalanceConfig(Condition rebalanceCondition,RebalanceAction rebalanceAction,RebalanceAutoCompound autoCompound,bool recurring)Condition(string type,int160 sqrtPriceX96,int64 timeBuffer,TickOffsetCondition tickOffsetCondition,PriceOffsetCondition priceOffsetCondition,TokenRatioCondition tokenRatioCondition)PriceOffsetAction(uint32 baseToken,int160 lowerOffsetSqrtPriceX96,int160 upperOffsetSqrtPriceX96)PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)RebalanceAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,string type,TickOffsetAction tickOffsetAction,PriceOffsetAction priceOffsetAction,TokenRatioAction tokenRatioAction)RebalanceAutoCompound(RebalanceAutoCompoundAction action)RebalanceAutoCompoundAction(int256 maxGasProportionX64,int256 feeToPrincipalRatioThresholdX64)TickOffsetAction(uint32 tickLowerOffset,uint32 tickUpperOffset)TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)TokenRatioAction(uint32 tickWidth,int256 token0RatioX64)TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant RebalanceConfig_TYPEHASH = 0xa595ef3200e4f62a94e521635728388988c00fa41a2fe6662a35a989b84c8507;
  struct RebalanceConfig {
    Condition rebalanceCondition;
    RebalanceAction rebalanceAction;
    RebalanceAutoCompound autoCompound;
    bool recurring;
  }
  function _hash(RebalanceConfig memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          RebalanceConfig_TYPEHASH,
          _hash(obj.rebalanceCondition),
          _hash(obj.rebalanceAction),
          _hash(obj.autoCompound),
          obj.recurring
        )
      );
  }

  // keccak256(
  //     "RangeOrderCondition(bool zeroToOne,int32 gteTickAbsolute,int32 lteTickAbsolute)"
  // );
  bytes32 constant RangeOrderCondition_TYPEHASH = 0xb6800e34595dae872617c5005f10a6a9e2b6a2520654db474bf4750fdd70a0c8;
  struct RangeOrderCondition {
    bool zeroToOne;
    int32 gteTickAbsolute;
    int32 lteTickAbsolute;
  }
  function _hash(RangeOrderCondition memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(RangeOrderCondition_TYPEHASH, obj.zeroToOne, obj.gteTickAbsolute, obj.lteTickAbsolute));
  }

  // keccak256(
  //     "RangeOrderAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 withdrawSlippageX64)"
  // );
  bytes32 constant RangeOrderAction_TYPEHASH = 0xf512215c27c5930c08d4f9d3f8d89d9b5735fb786bebf2231b3e88df5c4015d9;
  struct RangeOrderAction {
    int256 maxGasProportionX64;
    int256 swapSlippageX64;
    int256 withdrawSlippageX64;
  }
  function _hash(RangeOrderAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(RangeOrderAction_TYPEHASH, obj.maxGasProportionX64, obj.swapSlippageX64, obj.withdrawSlippageX64)
      );
  }

  // keccak256(
  //     "RangeOrderConfig(RangeOrderCondition condition,RangeOrderAction action)RangeOrderAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 withdrawSlippageX64)RangeOrderCondition(bool zeroToOne,int32 gteTickAbsolute,int32 lteTickAbsolute)"
  // );
  bytes32 constant RangeOrderConfig_TYPEHASH = 0x896dec1198540e9a29dda867832b7bb119f2cec50527c0f5ee63ef305b0f539a;
  struct RangeOrderConfig {
    RangeOrderCondition condition;
    RangeOrderAction action;
  }
  function _hash(RangeOrderConfig memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(RangeOrderConfig_TYPEHASH, _hash(obj.condition), _hash(obj.action)));
  }

  // keccak256(
  //     "FeeBasedCondition(int256 minFeeEarnedUsdX64)"
  // );
  bytes32 constant FeeBasedCondition_TYPEHASH = 0x0db5bdb29ccc0083eec5fc69273aba7a8fa98c12cb39bfa1377ade34a3b76e41;
  struct FeeBasedCondition {
    int256 minFeeEarnedUsdX64;
  }
  function _hash(FeeBasedCondition memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(FeeBasedCondition_TYPEHASH, obj.minFeeEarnedUsdX64));
  }

  // keccak256(
  //     "TimeBasedCondition(int256 intervalInSecond)"
  // );
  bytes32 constant TimeBasedCondition_TYPEHASH = 0xf75b2fc8dbd0e2a1eccdee6280f192941a296b909b47921d1a7c7cfd48993252;
  struct TimeBasedCondition {
    int256 intervalInSecond;
  }
  function _hash(TimeBasedCondition memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(TimeBasedCondition_TYPEHASH, obj.intervalInSecond));
  }

  // keccak256(
  //     "AutoCompoundCondition(string type,FeeBasedCondition feeBasedCondition,TimeBasedCondition timeBasedCondition)FeeBasedCondition(int256 minFeeEarnedUsdX64)TimeBasedCondition(int256 intervalInSecond)"
  // );
  bytes32 constant AutoCompoundCondition_TYPEHASH = 0x8077238253cf3aae9fc43bae69ede107dc9ecfe05cc3947a0cac4f94212a6223;
  struct AutoCompoundCondition {
    string _type;
    FeeBasedCondition feeBasedCondition;
    TimeBasedCondition timeBasedCondition;
  }
  function _hash(AutoCompoundCondition memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          AutoCompoundCondition_TYPEHASH,
          keccak256(bytes(obj._type)),
          _hash(obj.feeBasedCondition),
          _hash(obj.timeBasedCondition)
        )
      );
  }

  // keccak256(
  //     "AutoCompoundAction(int256 maxGasProportionX64,int256 poolSlippageX64,int256 swapSlippageX64)"
  // );
  bytes32 constant AutoCompoundAction_TYPEHASH = 0xe17b1ff10b4c0a0b457f201ae45a54a25ec9d424f9f0e068502ea1eab65d6e0e;
  struct AutoCompoundAction {
    int256 maxGasProportionX64;
    int256 poolSlippageX64;
    int256 swapSlippageX64;
  }
  function _hash(AutoCompoundAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(AutoCompoundAction_TYPEHASH, obj.maxGasProportionX64, obj.poolSlippageX64, obj.swapSlippageX64)
      );
  }

  // keccak256(
  //     "AutoCompoundConfig(AutoCompoundCondition condition,AutoCompoundAction action)AutoCompoundAction(int256 maxGasProportionX64,int256 poolSlippageX64,int256 swapSlippageX64)AutoCompoundCondition(string type,FeeBasedCondition feeBasedCondition,TimeBasedCondition timeBasedCondition)FeeBasedCondition(int256 minFeeEarnedUsdX64)TimeBasedCondition(int256 intervalInSecond)"
  // );
  bytes32 constant AutoCompoundConfig_TYPEHASH = 0xbf8ab0c4189cfff5a6148a64201555fddbb74f69f3c9ed9673c79357a2c77217;
  struct AutoCompoundConfig {
    AutoCompoundCondition condition;
    AutoCompoundAction action;
  }
  function _hash(AutoCompoundConfig memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(AutoCompoundConfig_TYPEHASH, _hash(obj.condition), _hash(obj.action)));
  }

  // keccak256(
  //     "AutoExitConfig(Condition condition,AutoExitAction action)AutoExitAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,address tokenOutAddress)Condition(string type,int160 sqrtPriceX96,int64 timeBuffer,TickOffsetCondition tickOffsetCondition,PriceOffsetCondition priceOffsetCondition,TokenRatioCondition tokenRatioCondition)PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant AutoExitConfig_TYPEHASH = 0x12abd614ffecf2dd5f160268162f92b4228cb34287cce8936339e98be3db7a86;
  struct AutoExitConfig {
    Condition condition;
    AutoExitAction action;
  }
  function _hash(AutoExitConfig memory obj) internal pure returns (bytes32) {
    return keccak256(abi.encode(AutoExitConfig_TYPEHASH, _hash(obj.condition), _hash(obj.action)));
  }

  // keccak256(
  //     "AutoExitAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,address tokenOutAddress)"
  // );
  bytes32 constant AutoExitAction_TYPEHASH = 0x335b4a1f07e5a10cc856257ff4116d238ebc816eb0189c48ede23eab0ba1b164;
  struct AutoExitAction {
    int256 maxGasProportionX64;
    int256 swapSlippageX64;
    int256 liquiditySlippageX64;
    address tokenOutAddress;
  }
  function _hash(AutoExitAction memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          AutoExitAction_TYPEHASH,
          obj.maxGasProportionX64,
          obj.swapSlippageX64,
          obj.liquiditySlippageX64,
          obj.tokenOutAddress
        )
      );
  }

  // keccak256(
  //     "OrderConfig(RebalanceConfig rebalanceConfig,RangeOrderConfig rangeOrderConfig,AutoCompoundConfig autoCompoundConfig,AutoExitConfig autoExitConfig)AutoCompoundAction(int256 maxGasProportionX64,int256 poolSlippageX64,int256 swapSlippageX64)AutoCompoundCondition(string type,FeeBasedCondition feeBasedCondition,TimeBasedCondition timeBasedCondition)AutoCompoundConfig(AutoCompoundCondition condition,AutoCompoundAction action)AutoExitAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,address tokenOutAddress)AutoExitConfig(Condition condition,AutoExitAction action)Condition(string type,int160 sqrtPriceX96,int64 timeBuffer,TickOffsetCondition tickOffsetCondition,PriceOffsetCondition priceOffsetCondition,TokenRatioCondition tokenRatioCondition)FeeBasedCondition(int256 minFeeEarnedUsdX64)PriceOffsetAction(uint32 baseToken,int160 lowerOffsetSqrtPriceX96,int160 upperOffsetSqrtPriceX96)PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)RangeOrderAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 withdrawSlippageX64)RangeOrderCondition(bool zeroToOne,int32 gteTickAbsolute,int32 lteTickAbsolute)RangeOrderConfig(RangeOrderCondition condition,RangeOrderAction action)RebalanceAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,string type,TickOffsetAction tickOffsetAction,PriceOffsetAction priceOffsetAction,TokenRatioAction tokenRatioAction)RebalanceAutoCompound(RebalanceAutoCompoundAction action)RebalanceAutoCompoundAction(int256 maxGasProportionX64,int256 feeToPrincipalRatioThresholdX64)RebalanceConfig(Condition rebalanceCondition,RebalanceAction rebalanceAction,RebalanceAutoCompound autoCompound,bool recurring)TickOffsetAction(uint32 tickLowerOffset,uint32 tickUpperOffset)TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)TimeBasedCondition(int256 intervalInSecond)TokenRatioAction(uint32 tickWidth,int256 token0RatioX64)TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant OrderConfig_TYPEHASH = 0x5697d3035f19beb9868f849a8299e5c537a4c0359a4de82d07077a2bb857f3bf;
  struct OrderConfig {
    RebalanceConfig rebalanceConfig;
    RangeOrderConfig rangeOrderConfig;
    AutoCompoundConfig autoCompoundConfig;
    AutoExitConfig autoExitConfig;
  }
  function _hash(OrderConfig memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          OrderConfig_TYPEHASH,
          _hash(obj.rebalanceConfig),
          _hash(obj.rangeOrderConfig),
          _hash(obj.autoCompoundConfig),
          _hash(obj.autoExitConfig)
        )
      );
  }

  // keccak256(
  //     "Order(int64 chainId,address nfpmAddress,uint256 tokenId,string orderType,OrderConfig config,int64 signatureTime)AutoCompoundAction(int256 maxGasProportionX64,int256 poolSlippageX64,int256 swapSlippageX64)AutoCompoundCondition(string type,FeeBasedCondition feeBasedCondition,TimeBasedCondition timeBasedCondition)AutoCompoundConfig(AutoCompoundCondition condition,AutoCompoundAction action)AutoExitAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,address tokenOutAddress)AutoExitConfig(Condition condition,AutoExitAction action)Condition(string type,int160 sqrtPriceX96,int64 timeBuffer,TickOffsetCondition tickOffsetCondition,PriceOffsetCondition priceOffsetCondition,TokenRatioCondition tokenRatioCondition)FeeBasedCondition(int256 minFeeEarnedUsdX64)OrderConfig(RebalanceConfig rebalanceConfig,RangeOrderConfig rangeOrderConfig,AutoCompoundConfig autoCompoundConfig,AutoExitConfig autoExitConfig)PriceOffsetAction(uint32 baseToken,int160 lowerOffsetSqrtPriceX96,int160 upperOffsetSqrtPriceX96)PriceOffsetCondition(uint32 baseToken,uint256 gteOffsetSqrtPriceX96,uint256 lteOffsetSqrtPriceX96)RangeOrderAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 withdrawSlippageX64)RangeOrderCondition(bool zeroToOne,int32 gteTickAbsolute,int32 lteTickAbsolute)RangeOrderConfig(RangeOrderCondition condition,RangeOrderAction action)RebalanceAction(int256 maxGasProportionX64,int256 swapSlippageX64,int256 liquiditySlippageX64,string type,TickOffsetAction tickOffsetAction,PriceOffsetAction priceOffsetAction,TokenRatioAction tokenRatioAction)RebalanceAutoCompound(RebalanceAutoCompoundAction action)RebalanceAutoCompoundAction(int256 maxGasProportionX64,int256 feeToPrincipalRatioThresholdX64)RebalanceConfig(Condition rebalanceCondition,RebalanceAction rebalanceAction,RebalanceAutoCompound autoCompound,bool recurring)TickOffsetAction(uint32 tickLowerOffset,uint32 tickUpperOffset)TickOffsetCondition(uint32 gteTickOffset,uint32 lteTickOffset)TimeBasedCondition(int256 intervalInSecond)TokenRatioAction(uint32 tickWidth,int256 token0RatioX64)TokenRatioCondition(int256 lteToken0RatioX64,int256 gteToken0RatioX64)"
  // );
  bytes32 constant Order_TYPEHASH = 0xe90c3305b073b571e7a0d9f03c551c07c8a7b94927ec80f7a2a5e4282b2153fa;
  struct Order {
    int64 chainId;
    address nfpmAddress;
    uint256 tokenId;
    string orderType;
    OrderConfig config;
    int64 signatureTime;
  }
  function _hash(Order memory obj) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          Order_TYPEHASH,
          obj.chainId,
          obj.nfpmAddress,
          obj.tokenId,
          keccak256(bytes(obj.orderType)),
          _hash(obj.config),
          obj.signatureTime
        )
      );
  }
}
