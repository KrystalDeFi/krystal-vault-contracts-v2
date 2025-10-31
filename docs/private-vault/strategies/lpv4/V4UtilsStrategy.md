# Solidity API

## V4UtilsStrategy

### v4UtilsRouter

```solidity
address v4UtilsRouter
```

### constructor

```solidity
constructor(address _v4UtilsRouter) public
```

### safeTransferNft

```solidity
function safeTransferNft(address posm, uint256 tokenId, bytes instruction, address[] withdrawTokens, address recipient) external payable
```

### execute

```solidity
function execute(address posm, bytes params, uint256 ethValue, address[] tokens, uint256[] approveAmounts) external payable
```

