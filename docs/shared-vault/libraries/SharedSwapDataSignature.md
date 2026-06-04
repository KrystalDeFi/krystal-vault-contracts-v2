# Solidity API

## SharedSwapDataSignature

### Envelope

```solidity
struct Envelope {
  bytes swapData;
  address vault;
  uint256 deadline;
  address signer;
  bytes signature;
}
```

### decode

```solidity
function decode(bytes signedSwapData) internal pure returns (struct SharedSwapDataSignature.Envelope envelope)
```

_Signed swapData envelope:
     abi.encode(bytes rawSwapData, address vault, uint256 deadline, address signer, bytes signature)_

### hash

```solidity
function hash(address vault, address signer, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes swapData, uint256 deadline) internal view returns (bytes32)
```

### verify

```solidity
function verify(contract ISharedConfigManager configManager, address expectedVault, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes signedSwapData) public view returns (bytes swapData)
```

