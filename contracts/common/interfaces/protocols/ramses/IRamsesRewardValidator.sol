// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Ramses' anti-sybil reward validator. A gauge asks it about every claim and forfeits the claim when it
///         answers true (or reverts). Its rules (a minimum time since the position's last liquidity change, and
///         wallet / position blacklists) are upgradeable and not published as source.
interface IRamsesRewardValidator {
  /// @param owner The pool-level owner of the position: the position manager
  /// @param receiver Where the claim would be paid: the NFT's owner
  /// @param positionHash keccak256(abi.encodePacked(owner, index, tickLower, tickUpper))
  /// @param origin The claim transaction's tx.origin
  /// @param index The position's tokenId
  /// @return slash True when the claim would be forfeited
  function validateReward(
    address owner,
    address receiver,
    bytes32 positionHash,
    address origin,
    uint256 index,
    int24 tickLower,
    int24 tickUpper,
    address pool
  ) external view returns (bool slash);
}
