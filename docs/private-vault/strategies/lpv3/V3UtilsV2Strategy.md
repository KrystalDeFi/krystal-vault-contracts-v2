# Solidity API

## V3UtilsV2Strategy

### v3utils

```solidity
address v3utils
```

### constructor

```solidity
constructor(address _v3utils) public
```

### safeTransferNft

```solidity
function safeTransferNft(address _nfpm, uint256 tokenId, bytes instructions) external
```

### swapAndMint

```solidity
function swapAndMint(struct IV3UtilsV2.SwapAndMintParams params, uint256 ethValue, address[] tokens, uint256[] amounts) external payable returns (struct IV3UtilsV2.SwapAndMintResult)
```

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct IV3UtilsV2.SwapAndIncreaseLiquidityParams params, uint256 ethValue, address[] tokens, uint256[] amounts) external payable returns (struct IV3UtilsV2.SwapAndIncreaseLiquidityResult)
```

### _approveTokens

```solidity
function _approveTokens(address[] tokens, uint256[] approveAmounts, address target) internal
```

