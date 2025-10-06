# Solidity API

## V3UtilsStrategy

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
function safeTransferNft(address _nfpm, uint256 tokenId, struct IV3Utils.Instructions instructions) external
```

### swapAndMint

```solidity
function swapAndMint(struct IV3Utils.SwapAndMintParams params, uint256 ethValue, address[] tokens, uint256[] amounts) external payable returns (struct IV3Utils.SwapAndMintResult)
```

### swapAndIncreaseLiquidity

```solidity
function swapAndIncreaseLiquidity(struct IV3Utils.SwapAndIncreaseLiquidityParams params, uint256 ethValue, address[] tokens, uint256[] amounts) external payable returns (struct IV3Utils.SwapAndIncreaseLiquidityResult)
```

### _approveTokens

```solidity
function _approveTokens(address[] tokens, uint256[] approveAmounts, address target) internal
```

