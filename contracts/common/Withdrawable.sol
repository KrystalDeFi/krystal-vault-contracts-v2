// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title Withdrawable
 * @notice Abstract contract providing sweep functions for native tokens, ERC20, ERC721, and ERC1155 tokens
 * @dev Child contracts must implement the `_checkWithdrawPermission` modifier to enforce access control
 */
abstract contract Withdrawable {
  using SafeERC20 for IERC20;

  error ArrayLengthMismatch();

  /// @dev Modifier to check if the caller has permission to withdraw
  /// @dev Must be implemented by the child contract
  modifier onlyWithdrawer() {
    _checkWithdrawPermission();
    _;
  }

  /// @notice Check if the caller has permission to withdraw
  /// @dev Must be implemented by the child contract
  function _checkWithdrawPermission() internal view virtual;

  /// @notice Sweep native token to the caller
  /// @param amount Amount of native token to sweep
  function sweepNativeToken(uint256 amount) external onlyWithdrawer {
    uint256 balance = address(this).balance;
    if (amount > balance) amount = balance;

    (bool success, ) = msg.sender.call{ value: amount }("");
    require(success, "Failed to send native token");
  }

  /// @notice Sweeps ERC20 tokens to the caller
  /// @param tokens Tokens to sweep
  /// @param amounts Amounts of tokens to sweep
  function sweepERC20(address[] calldata tokens, uint256[] memory amounts) external onlyWithdrawer {
    if (tokens.length != amounts.length) revert ArrayLengthMismatch();

    for (uint256 i; i < tokens.length; ) {
      require(tokens[i] != address(0), "ZeroAddress");
      IERC20 token = IERC20(tokens[i]);
      uint256 balance = token.balanceOf(address(this));
      if (amounts[i] > balance) amounts[i] = balance;
      token.safeTransfer(msg.sender, amounts[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweeps ERC721 tokens to the caller
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  function sweepERC721(address[] calldata tokens, uint256[] calldata tokenIds) external onlyWithdrawer {
    if (tokens.length != tokenIds.length) revert ArrayLengthMismatch();

    for (uint256 i; i < tokens.length; ) {
      require(tokens[i] != address(0), "ZeroAddress");
      IERC721 token = IERC721(tokens[i]);
      token.safeTransferFrom(address(this), msg.sender, tokenIds[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweeps ERC1155 tokens to the caller
  /// @param tokens Tokens to sweep
  /// @param tokenIds Token IDs to sweep
  /// @param amounts Amounts of tokens to sweep
  function sweepERC1155(
    address[] calldata tokens,
    uint256[] calldata tokenIds,
    uint256[] memory amounts
  ) external onlyWithdrawer {
    if (tokens.length != tokenIds.length) revert ArrayLengthMismatch();
    if (tokens.length != amounts.length) revert ArrayLengthMismatch();

    for (uint256 i; i < tokens.length; ) {
      require(tokens[i] != address(0), "ZeroAddress");
      IERC1155 token = IERC1155(tokens[i]);
      uint256 balance = token.balanceOf(address(this), tokenIds[i]);
      if (amounts[i] > balance) amounts[i] = balance;
      token.safeTransferFrom(address(this), msg.sender, tokenIds[i], amounts[i], "");

      unchecked {
        i++;
      }
    }
  }
}
