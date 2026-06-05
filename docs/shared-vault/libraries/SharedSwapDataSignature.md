# Solidity API

## SharedSwapDataSignature

### STORAGE_SLOT

```solidity
bytes32 STORAGE_SLOT
```

_Replay-protection storage namespace:
     keccak256("krystal.shared-vault.swap-data-signature.storage")._

### Layout

```solidity
struct Layout {
  mapping(bytes32 => bool) consumedDigests;
}
```

### Envelope

```solidity
struct Envelope {
  bytes swapData;
  address vault;
  uint256 deadline;
  address signer;
  bytes32 nonce;
  bytes signature;
}
```

### decode

```solidity
function decode(bytes signedSwapData) internal pure returns (struct SharedSwapDataSignature.Envelope envelope)
```

_Signed envelope: abi.encode(rawSwapData, vault, deadline, signer, nonce, signature)._

### layout

```solidity
function layout() internal pure returns (struct SharedSwapDataSignature.Layout l)
```

### hash

```solidity
function hash(address vault, address signer, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes swapData, uint256 deadline, bytes32 nonce) internal view returns (bytes32)
```

### verify

```solidity
function verify(contract ISharedConfigManager configManager, address expectedVault, address swapRouter, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes signedSwapData) public returns (bytes swapData)
```

