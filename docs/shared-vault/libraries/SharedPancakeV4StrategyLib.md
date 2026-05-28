# Solidity API

## PancakeV4Actions

### INCREASE_LIQUIDITY

```solidity
uint8 INCREASE_LIQUIDITY
```

### DECREASE_LIQUIDITY

```solidity
uint8 DECREASE_LIQUIDITY
```

### MINT_POSITION

```solidity
uint8 MINT_POSITION
```

### SETTLE_PAIR

```solidity
uint8 SETTLE_PAIR
```

### TAKE_PAIR

```solidity
uint8 TAKE_PAIR
```

### CLOSE_CURRENCY

```solidity
uint8 CLOSE_CURRENCY
```

## SharedPancakeV4StrategyLib

### FeeCollected

```solidity
event FeeCollected(address vaultAddress, enum IFeeTaker.FeeType feeType, address recipient, address token, uint256 amount)
```

### depositProportional

```solidity
function depositProportional(address posm, uint256 tokenId, uint256 amount0, uint256 amount1, uint16 slippageBps) external
```

### collectFees

```solidity
function collectFees(address posm, uint256 tokenId, struct ICommon.FeeConfig fc) external
```

### executeCalldata

```solidity
function executeCalldata(address swapRouter, address posm, uint256 tokenId, bytes params) external
```

### executeInstructionBytes

```solidity
function executeInstructionBytes(address swapRouter, address posm, uint256 tokenId, bytes instruction) external
```

### swapAndMintCalldata

```solidity
function swapAndMintCalldata(address swapRouter, address posm, bytes params) external
```

### swapAndIncreaseCalldata

```solidity
function swapAndIncreaseCalldata(address swapRouter, address posm, uint256 tokenId, bytes params) external
```

### exitProportional

```solidity
function exitProportional(address posm, uint256 tokenId, uint256 shares, uint256 totalShares, uint256 minAmount0, uint256 minAmount1) external returns (struct ISharedStrategy.PositionChange[] changes)
```

### getPositionAmounts

```solidity
function getPositionAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

### getPositionPrincipalAmounts

```solidity
function getPositionPrincipalAmounts(address posm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1)
```

