// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./CustomEIP712.sol";
import "../../interfaces/core/IVaultAutomator.sol";
import "../../interfaces/strategies/ILpStrategy.sol";

/**
 * @title VaultAutomator
 * @notice Contract that automates vault operations for liquidity provision and management
 */
contract VaultAutomator is CustomEIP712, AccessControl, Pausable, ERC721Holder, ERC1155Holder, IVaultAutomator {
  using SafeERC20 for IERC20;

  bytes32 public constant OPERATOR_ROLE_HASH = keccak256("OPERATOR_ROLE");

  mapping(bytes32 => bool) private _cancelledOrder;

  constructor(address _owner, address[] memory _operators) CustomEIP712("V3AutomationOrder", "4.0") {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(OPERATOR_ROLE_HASH, _owner);
    for (uint256 i = 0; i < _operators.length; i++) {
      _grantRole(OPERATOR_ROLE_HASH, _operators[i]);
    }
  }

  /// @notice Execute an allocate on a Vault
  /// @param vault Vault
  /// @param inputAssets Input assets
  /// @param strategy Strategy
  /// @param allocateData allocateData data to be passed to vault's allocate function
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function executeAllocate(
    IVault vault,
    AssetLib.Asset[] memory inputAssets,
    IStrategy strategy,
    uint64 gasFeeX64,
    bytes calldata allocateData,
    bytes calldata abiEncodedUserOrder,
    bytes calldata orderSignature
  ) external onlyRole(OPERATOR_ROLE_HASH) whenNotPaused {
    _validateOrder(abiEncodedUserOrder, orderSignature, vault.vaultOwner());
    Instruction memory instruction = abi.decode(allocateData, (Instruction));
    require(
      instruction.instructionType == uint8(ILpStrategy.InstructionType.SwapAndRebalancePosition)
        || instruction.instructionType == uint8(ILpStrategy.InstructionType.SwapAndCompound)
        || instruction.instructionType == uint8(ILpStrategy.InstructionType.DecreaseLiquidityAndSwap),
      InvalidInstructionType()
    );
    vault.allocate(inputAssets, strategy, gasFeeX64, allocateData);
  }

  /// @notice Execute sweep token
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  function executeSweepToken(IVault vault, address[] memory tokens) external override onlyRole(OPERATOR_ROLE_HASH) {
    vault.sweepToken(tokens);

    uint256 length = tokens.length;

    for (uint256 i; i < length;) {
      IERC20 token = IERC20(tokens[i]);
      token.safeTransfer(_msgSender(), token.balanceOf(address(this)));

      unchecked {
        i++;
      }
    }
  }

  /// @notice Execute sweep NFT token ERC721
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  function executeSweepERC721(IVault vault, address[] memory tokens, uint256[] memory tokenIds)
    external
    override
    onlyRole(OPERATOR_ROLE_HASH)
  {
    vault.sweepERC721(tokens, tokenIds);

    uint256 length = tokens.length;

    for (uint256 i; i < length;) {
      IERC721 token = IERC721(tokens[i]);
      token.safeTransferFrom(address(this), _msgSender(), tokenIds[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Execute sweep NFT token ERC1155
  /// @param vault Vault address
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  function executeSweepERC1155(IVault vault, address[] memory tokens, uint256[] memory tokenIds)
    external
    override
    onlyRole(OPERATOR_ROLE_HASH)
  {
    vault.sweepERC1155(tokens, tokenIds);

    uint256 length = tokens.length;

    for (uint256 i; i < length;) {
      IERC1155 token = IERC1155(tokens[i]);
      token.safeTransferFrom(address(this), _msgSender(), tokenIds[i], token.balanceOf(address(this), tokenIds[i]), "");

      unchecked {
        i++;
      }
    }
  }

  /// @dev Validate the order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  /// @param actor Actor of the order
  function _validateOrder(bytes memory abiEncodedUserOrder, bytes memory orderSignature, address actor) internal view {
    address userAddress = _recover(abiEncodedUserOrder, orderSignature);
    require(userAddress == actor, InvalidSignature());
    require(!_cancelledOrder[keccak256(orderSignature)], OrderCancelled());
  }

  /// @notice Cancel an order
  /// @param abiEncodedUserOrder ABI encoded user order
  /// @param orderSignature Signature of the order
  function cancelOrder(bytes calldata abiEncodedUserOrder, bytes calldata orderSignature) external {
    _validateOrder(abiEncodedUserOrder, orderSignature, msg.sender);
    _cancelledOrder[keccak256(orderSignature)] = true;
    emit CancelOrder(msg.sender, abiEncodedUserOrder, orderSignature);
  }

  /// @notice Check if an order is cancelled
  /// @param orderSignature Signature of the order
  /// @return true if the order is cancelled
  function isOrderCancelled(bytes calldata orderSignature) external view returns (bool) {
    return _cancelledOrder[keccak256(orderSignature)];
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

  /// @notice Pause the contract
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpause the contract
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
  }

  receive() external payable { }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControl, ERC1155Holder)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
