// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IMerklStrategy } from "../../interfaces/strategies/IMerklStrategy.sol";
import { IVault } from "../../interfaces/core/IVault.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ICommon } from "../../interfaces/ICommon.sol";
import { AssetLib } from "../../libraries/AssetLib.sol";

/**
 * @title MerklAutoClaimer
 * @notice Contract that allows anyone to trigger Merkl reward claims through vault allocation
 */
contract MerklAutoClaimer is Pausable, AccessControl {
  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(address => bool) private allowedStrategies;

  constructor(address[] memory _allowedStrategies, address _owner) {
    for (uint256 i = 0; i < _allowedStrategies.length; i++) {
      allowedStrategies[_allowedStrategies[i]] = true;
    }
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
  }

  /**
   * @notice Claim Merkl rewards on behalf of a vault
   * @param vault The vault to claim rewards for
   * @param claimAndSwapParams Parameters for the Merkl reward claim
   */
  function claimRewards(
    IVault vault,
    address mekleStrategy,
    IMerklStrategy.ClaimAndSwapParams memory claimAndSwapParams
  ) external {
    require(allowedStrategies[mekleStrategy], ICommon.InvalidStrategy());
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap),
      params: abi.encode(claimAndSwapParams)
    });
    AssetLib.Asset[] memory emptyAssets = new AssetLib.Asset[](0);
    vault.allocate(emptyAssets, IMerklStrategy(mekleStrategy), 0, abi.encode(instruction));
  }

  /// @notice Grant operator role
  /// @param operator Operator address
  function grantOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    grantRole(OPERATOR_ROLE_HASH, operator);
  }

  /// @notice Revoke operator role
  /// @param operator Operator address
  function revokeOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(OPERATOR_ROLE_HASH, operator);
  }
}
