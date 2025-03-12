# Solidity API

## StructHash

### \_hash

```solidity
function _hash(bytes abiEncodedUserOrder) internal pure returns (bytes32)
```

### RebalanceAutoCompound_TYPEHASH

```solidity
bytes32 RebalanceAutoCompound_TYPEHASH
```

### RebalanceAutoCompound

```solidity
struct RebalanceAutoCompound {
  struct StructHash.RebalanceAutoCompoundAction action;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RebalanceAutoCompound obj) internal pure returns (bytes32)
```

### RebalanceAutoCompoundAction_TYPEHASH

```solidity
bytes32 RebalanceAutoCompoundAction_TYPEHASH
```

### RebalanceAutoCompoundAction

```solidity
struct RebalanceAutoCompoundAction {
  int256 maxGasProportionX64;
  int256 feeToPrincipalRatioThresholdX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RebalanceAutoCompoundAction obj) internal pure returns (bytes32)
```

### TickOffsetCondition_TYPEHASH

```solidity
bytes32 TickOffsetCondition_TYPEHASH
```

### TickOffsetCondition

```solidity
struct TickOffsetCondition {
  uint32 gteTickOffset;
  uint32 lteTickOffset;
}
```

### \_hash

```solidity
function _hash(struct StructHash.TickOffsetCondition obj) internal pure returns (bytes32)
```

### PriceOffsetCondition_TYPEHASH

```solidity
bytes32 PriceOffsetCondition_TYPEHASH
```

### PriceOffsetCondition

```solidity
struct PriceOffsetCondition {
  uint32 baseToken;
  uint256 gteOffsetSqrtPriceX96;
  uint256 lteOffsetSqrtPriceX96;
}
```

### \_hash

```solidity
function _hash(struct StructHash.PriceOffsetCondition obj) internal pure returns (bytes32)
```

### TokenRatioCondition_TYPEHASH

```solidity
bytes32 TokenRatioCondition_TYPEHASH
```

### TokenRatioCondition

```solidity
struct TokenRatioCondition {
  int256 lteToken0RatioX64;
  int256 gteToken0RatioX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.TokenRatioCondition obj) internal pure returns (bytes32)
```

### Condition_TYPEHASH

```solidity
bytes32 Condition_TYPEHASH
```

### Condition

```solidity
struct Condition {
  string _type;
  int160 sqrtPriceX96;
  int64 timeBuffer;
  struct StructHash.TickOffsetCondition tickOffsetCondition;
  struct StructHash.PriceOffsetCondition priceOffsetCondition;
  struct StructHash.TokenRatioCondition tokenRatioCondition;
}
```

### \_hash

```solidity
function _hash(struct StructHash.Condition obj) internal pure returns (bytes32)
```

### TickOffsetAction_TYPEHASH

```solidity
bytes32 TickOffsetAction_TYPEHASH
```

### TickOffsetAction

```solidity
struct TickOffsetAction {
  uint32 tickLowerOffset;
  uint32 tickUpperOffset;
}
```

### \_hash

```solidity
function _hash(struct StructHash.TickOffsetAction obj) internal pure returns (bytes32)
```

### PriceOffsetAction_TYPEHASH

```solidity
bytes32 PriceOffsetAction_TYPEHASH
```

### PriceOffsetAction

```solidity
struct PriceOffsetAction {
  uint32 baseToken;
  int160 lowerOffsetSqrtPriceX96;
  int160 upperOffsetSqrtPriceX96;
}
```

### \_hash

```solidity
function _hash(struct StructHash.PriceOffsetAction obj) internal pure returns (bytes32)
```

### TokenRatioAction_TYPEHASH

```solidity
bytes32 TokenRatioAction_TYPEHASH
```

### TokenRatioAction

```solidity
struct TokenRatioAction {
  uint32 tickWidth;
  int256 token0RatioX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.TokenRatioAction obj) internal pure returns (bytes32)
```

### RebalanceAction_TYPEHASH

```solidity
bytes32 RebalanceAction_TYPEHASH
```

### RebalanceAction

```solidity
struct RebalanceAction {
  int256 maxGasProportionX64;
  int256 swapSlippageX64;
  int256 liquiditySlippageX64;
  string _type;
  struct StructHash.TickOffsetAction tickOffsetAction;
  struct StructHash.PriceOffsetAction priceOffsetAction;
  struct StructHash.TokenRatioAction tokenRatioAction;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RebalanceAction obj) internal pure returns (bytes32)
```

### RebalanceConfig_TYPEHASH

```solidity
bytes32 RebalanceConfig_TYPEHASH
```

### RebalanceConfig

```solidity
struct RebalanceConfig {
  struct StructHash.Condition rebalanceCondition;
  struct StructHash.RebalanceAction rebalanceAction;
  struct StructHash.RebalanceAutoCompound autoCompound;
  bool recurring;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RebalanceConfig obj) internal pure returns (bytes32)
```

### RangeOrderCondition_TYPEHASH

```solidity
bytes32 RangeOrderCondition_TYPEHASH
```

### RangeOrderCondition

```solidity
struct RangeOrderCondition {
  bool zeroToOne;
  int32 gteTickAbsolute;
  int32 lteTickAbsolute;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RangeOrderCondition obj) internal pure returns (bytes32)
```

### RangeOrderAction_TYPEHASH

```solidity
bytes32 RangeOrderAction_TYPEHASH
```

### RangeOrderAction

```solidity
struct RangeOrderAction {
  int256 maxGasProportionX64;
  int256 swapSlippageX64;
  int256 withdrawSlippageX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RangeOrderAction obj) internal pure returns (bytes32)
```

### RangeOrderConfig_TYPEHASH

```solidity
bytes32 RangeOrderConfig_TYPEHASH
```

### RangeOrderConfig

```solidity
struct RangeOrderConfig {
  struct StructHash.RangeOrderCondition condition;
  struct StructHash.RangeOrderAction action;
}
```

### \_hash

```solidity
function _hash(struct StructHash.RangeOrderConfig obj) internal pure returns (bytes32)
```

### FeeBasedCondition_TYPEHASH

```solidity
bytes32 FeeBasedCondition_TYPEHASH
```

### FeeBasedCondition

```solidity
struct FeeBasedCondition {
  int256 minFeeEarnedUsdX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.FeeBasedCondition obj) internal pure returns (bytes32)
```

### TimeBasedCondition_TYPEHASH

```solidity
bytes32 TimeBasedCondition_TYPEHASH
```

### TimeBasedCondition

```solidity
struct TimeBasedCondition {
  int256 intervalInSecond;
}
```

### \_hash

```solidity
function _hash(struct StructHash.TimeBasedCondition obj) internal pure returns (bytes32)
```

### AutoCompoundCondition_TYPEHASH

```solidity
bytes32 AutoCompoundCondition_TYPEHASH
```

### AutoCompoundCondition

```solidity
struct AutoCompoundCondition {
  string _type;
  struct StructHash.FeeBasedCondition feeBasedCondition;
  struct StructHash.TimeBasedCondition timeBasedCondition;
}
```

### \_hash

```solidity
function _hash(struct StructHash.AutoCompoundCondition obj) internal pure returns (bytes32)
```

### AutoCompoundAction_TYPEHASH

```solidity
bytes32 AutoCompoundAction_TYPEHASH
```

### AutoCompoundAction

```solidity
struct AutoCompoundAction {
  int256 maxGasProportionX64;
  int256 poolSlippageX64;
  int256 swapSlippageX64;
}
```

### \_hash

```solidity
function _hash(struct StructHash.AutoCompoundAction obj) internal pure returns (bytes32)
```

### AutoCompoundConfig_TYPEHASH

```solidity
bytes32 AutoCompoundConfig_TYPEHASH
```

### AutoCompoundConfig

```solidity
struct AutoCompoundConfig {
  struct StructHash.AutoCompoundCondition condition;
  struct StructHash.AutoCompoundAction action;
}
```

### \_hash

```solidity
function _hash(struct StructHash.AutoCompoundConfig obj) internal pure returns (bytes32)
```

### AutoExitConfig_TYPEHASH

```solidity
bytes32 AutoExitConfig_TYPEHASH
```

### AutoExitConfig

```solidity
struct AutoExitConfig {
  struct StructHash.Condition condition;
  struct StructHash.AutoExitAction action;
}
```

### \_hash

```solidity
function _hash(struct StructHash.AutoExitConfig obj) internal pure returns (bytes32)
```

### AutoExitAction_TYPEHASH

```solidity
bytes32 AutoExitAction_TYPEHASH
```

### AutoExitAction

```solidity
struct AutoExitAction {
  int256 maxGasProportionX64;
  int256 swapSlippageX64;
  int256 liquiditySlippageX64;
  address tokenOutAddress;
}
```

### \_hash

```solidity
function _hash(struct StructHash.AutoExitAction obj) internal pure returns (bytes32)
```

### OrderConfig_TYPEHASH

```solidity
bytes32 OrderConfig_TYPEHASH
```

### OrderConfig

```solidity
struct OrderConfig {
  struct StructHash.RebalanceConfig rebalanceConfig;
  struct StructHash.RangeOrderConfig rangeOrderConfig;
  struct StructHash.AutoCompoundConfig autoCompoundConfig;
  struct StructHash.AutoExitConfig autoExitConfig;
}
```

### \_hash

```solidity
function _hash(struct StructHash.OrderConfig obj) internal pure returns (bytes32)
```

### Order_TYPEHASH

```solidity
bytes32 Order_TYPEHASH
```

### Order

```solidity
struct Order {
  int64 chainId;
  address nfpmAddress;
  uint256 tokenId;
  string orderType;
  struct StructHash.OrderConfig config;
  int64 signatureTime;
}
```

### \_hash

```solidity
function _hash(struct StructHash.Order obj) internal pure returns (bytes32)
```
