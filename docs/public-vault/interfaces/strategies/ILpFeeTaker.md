# Solidity API

## ILpFeeTaker

### SwapToPrincipalParams

```solidity
struct SwapToPrincipalParams {
  address pool;
  address principalToken;
  address token;
  uint256 amount;
  uint256 amountOutMin;
  bytes swapData;
}
```

### takeFees

```solidity
function takeFees(address token0, uint256 amount0, address token1, uint256 amount1, struct ICommon.FeeConfig feeConfig, address principalToken, address pool, address validator) external returns (uint256 fee0, uint256 fee1)
```

