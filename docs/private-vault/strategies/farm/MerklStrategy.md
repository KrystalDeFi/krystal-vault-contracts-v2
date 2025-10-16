# Solidity API

## MerklStrategy

Strategy for handling Merkl rewards for LP positions

### distributor

```solidity
address distributor
```

### configManager

```solidity
contract IPrivateConfigManager configManager
```

### MerklRewardClaim

```solidity
event MerklRewardClaim(address distributor, address token, uint256 amount)
```

### constructor

```solidity
constructor(address _distributor, address _configManager) public
```

### claimMerkleReward

```solidity
function claimMerkleReward(address token, uint256 amount, bytes32[] proofs, uint16 feeBps) external
```

