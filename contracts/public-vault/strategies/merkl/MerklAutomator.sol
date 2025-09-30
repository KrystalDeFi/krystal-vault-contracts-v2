// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../../interfaces/core/IConfigManager.sol";
import "../../interfaces/strategies/IMerklStrategy.sol";
import "../../interfaces/strategies/IMerklAutomator.sol";

/**
 * @title MerklAutomator
 * @notice Contract that allows anyone to trigger Merkl reward claims through vault allocation
 */
contract MerklAutomator is Ownable, Pausable, IMerklAutomator {
  IConfigManager public configManager;

  constructor(address _owner, address _configManager) Ownable(_owner) {
    require(_configManager != address(0), ZeroAddress());

    configManager = IConfigManager(_configManager);
  }

  /// @notice Execute an allocate on a Vault
  /// @param vault Vault
  /// @param inputAssets Input assets
  /// @param strategy Strategy
  /// @param allocateData allocateData data to be passed to vault's allocate function
  function executeAllocate(
    IVault vault,
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    uint64 gasFeeX64,
    bytes calldata allocateData,
    bytes calldata,
    bytes calldata
  ) external whenNotPaused {
    require(inputAssets.length == 0, InvalidAssetStrategy());
    Instruction memory instruction = abi.decode(allocateData, (Instruction));
    require(instruction.instructionType == uint8(IMerklStrategy.InstructionType.ClaimAndSwap), InvalidInstructionType());
    IMerklStrategy.ClaimAndSwapParams memory claimParams =
      abi.decode(instruction.params, (IMerklStrategy.ClaimAndSwapParams));

    // Verify the signer is whitelisted
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        claimParams.distributor,
        claimParams.token,
        claimParams.amount,
        claimParams.proof,
        claimParams.swapRouter,
        claimParams.swapData,
        claimParams.amountOutMin,
        claimParams.deadline
      )
    );
    address signer = ECDSA.recover(messageHash, claimParams.signature);
    require(configManager.isWhitelistSigner(signer), InvalidSigner());
    require(block.timestamp <= claimParams.deadline, SignatureExpired());

    vault.allocate(inputAssets, strategy, gasFeeX64, allocateData);
  }

  /// @notice Pause the contract
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Unpause the contract
  function unpause() external onlyOwner {
    _unpause();
  }
}
