# Solidity API

## IRamsesRewardValidator

Ramses' anti-sybil reward validator. A gauge asks it about every claim and forfeits the claim when it
        answers true (or reverts). Its rules (a minimum time since the position's last liquidity change, and
        wallet / position blacklists) are upgradeable and not published as source.

### validateReward

```solidity
function validateReward(address owner, address receiver, bytes32 positionHash, address origin, uint256 index, int24 tickLower, int24 tickUpper, address pool) external view returns (bool slash)
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | address | The pool-level owner of the position: the position manager |
| receiver | address | Where the claim would be paid: the NFT's owner |
| positionHash | bytes32 | keccak256(abi.encodePacked(owner, index, tickLower, tickUpper)) |
| origin | address | The claim transaction's tx.origin |
| index | uint256 | The position's tokenId |
| tickLower | int24 |  |
| tickUpper | int24 |  |
| pool | address |  |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| slash | bool | True when the claim would be forfeited |

