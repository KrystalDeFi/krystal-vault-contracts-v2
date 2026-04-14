// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { ISharedCommon } from "../interfaces/ISharedCommon.sol";

/// @title SharedV3SafeTransferNftLib
/// @notice Helpers for `Shared*Strategy._safeTransferNft` (CHANGE_RANGE + full exit).
library SharedV3SafeTransferNftLib {
  /// @dev Last global NFPM id before a mint: `tokenByIndex(totalSupply() - 1)`; strategies use `+ 1` as `newTokenId`.
  ///      `nfpm` must be `IERC721Enumerable`.
  function lastGlobalNfpmTokenId(address nfpm) internal view returns (uint256 lastId) {
    if (!IERC165(nfpm).supportsInterface(type(IERC721Enumerable).interfaceId)) {
      revert ISharedCommon.NfpmEnumerableRequired();
    }
    uint256 n = IERC721Enumerable(nfpm).totalSupply();
    if (n == 0) return 0;
    return IERC721Enumerable(nfpm).tokenByIndex(n - 1);
  }

  function nfpmNftStillHeldByVault(address nfpm, uint256 tokenId, address vault) internal view returns (bool) {
    try IERC721(nfpm).ownerOf(tokenId) returns (address owner) {
      return owner == vault;
    } catch {
      return false;
    }
  }
}
