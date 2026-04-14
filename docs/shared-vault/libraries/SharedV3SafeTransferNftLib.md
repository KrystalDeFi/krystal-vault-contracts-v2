# Solidity API

## SharedV3SafeTransferNftLib

Helpers for `Shared*Strategy._safeTransferNft` (CHANGE_RANGE + full exit).

### lastGlobalNfpmTokenId

```solidity
function lastGlobalNfpmTokenId(address nfpm) internal view returns (uint256 lastId)
```

_Last global NFPM id before a mint: `tokenByIndex(totalSupply() - 1)`; strategies use `+ 1` as `newTokenId`.
     `nfpm` must be `IERC721Enumerable`._

### nfpmNftStillHeldByVault

```solidity
function nfpmNftStillHeldByVault(address nfpm, uint256 tokenId, address vault) internal view returns (bool)
```

