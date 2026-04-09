// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import "../interfaces/ISharedVault.sol";
import "../../public-vault/interfaces/IWETH9.sol";

/// @title SharedVaultGateway
/// @notice Simplifies deposits into and withdrawals from SharedVault by accepting arbitrary
///         input tokens and executing pre-built swap calldata (from an off-chain aggregator API)
///         to convert them into the vault's required proportional token mix.
///
/// Deposit flow:  user sends any tokens → gateway swaps to vault tokens → deposits to vault → returns shares + leftovers
/// Withdraw flow: user burns shares via gateway → receives vault tokens → gateway swaps to desired output → returns output + leftovers
contract SharedVaultGateway is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  // ==================== Errors ====================

  error ZeroAddress();
  error SwapFailed(uint256 index);
  error SlippageExceeded(uint256 index);
  error InsufficientShares();
  error InvalidSwapRouter();
  error InsufficientMsgValue();
  error InsufficientPostSwapBalance(uint256 tokenIndex);
  error EthTransferFailed();

  // ==================== Events ====================

  event SwapAndDeposit(address indexed vault, address indexed depositor, uint256 sharesReceived);

  event WithdrawAndSwap(address indexed vault, address indexed withdrawer, uint256 sharesBurned);

  event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);

  // ==================== Structs ====================

  /// @param tokenIn ERC20 to pull from the user, or `address(0)` for native ETH (consumed from `msg.value`).
  ///                WETH as ERC20 must use `tokenIn == weth` and is always pulled via `transferFrom`, never mixed with `msg.value`.
  struct SwapParams {
    address tokenIn;
    uint256 amountIn; // 0 = use full balance of tokenIn held by gateway
    address tokenOut;
    uint256 amountOutMin;
    bytes swapData; // calldata for swapRouter; empty = skip (e.g. WETH↔ETH wrap)
  }

  struct SwapAndDepositParams {
    ISharedVault vault;
    SwapParams[] swaps;
    /// @notice Per vault-token slot: minimum balance the gateway must hold after swaps (slippage floor).
    ///         If actual balance is below this for a configured vault token, the call reverts before `deposit`.
    ///         Pass 0 to skip the check for that slot. Actual amounts sent to the vault are always the
    ///         gateway's current ERC20 balances (never inflated above balance).
    uint256[4] minDepositAmounts;
    uint16 slippageBps;
    uint256 minShares;
    address[] sweepTokens; // tokens to return leftovers for (vault tokens + any intermediaries)
  }

  struct WithdrawAndSwapParams {
    ISharedVault vault;
    uint256 shares;
    uint256[4] minWithdrawAmounts; // slippage guard for vault.withdraw()
    bool unwrapOnWithdraw; // unwrap WETH to ETH during vault.withdraw()
    SwapParams[] swaps;
    address[] sweepTokens; // tokens to return leftovers for
  }

  // ==================== State ====================

  address public swapRouter;
  address public weth;

  // ==================== Initializer ====================

  function initialize(address _owner, address _swapRouter, address _weth) external initializer {
    require(_owner != address(0), ZeroAddress());
    require(_swapRouter != address(0), ZeroAddress());
    require(_weth != address(0), ZeroAddress());

    __Ownable_init(_owner);
    __ReentrancyGuard_init();
    __Pausable_init();

    swapRouter = _swapRouter;
    weth = _weth;
  }

  // ==================== Admin ====================

  function setSwapRouter(address _swapRouter) external onlyOwner {
    require(_swapRouter != address(0), InvalidSwapRouter());
    emit SwapRouterUpdated(swapRouter, _swapRouter);
    swapRouter = _swapRouter;
  }

  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }

  // ==================== Deposit Flow ====================

  /// @notice Pull input tokens, execute swaps to vault tokens, deposit proportionally, return leftovers.
  /// @dev Swap calldata is built off-chain by the Krystal API swap aggregator.
  ///      The gateway briefly holds tokens during the tx; nothing persists across calls.
  ///      **ETH**: `msg.value` must be at least the sum of `amountIn` on swaps with `tokenIn == address(0)`;
  ///      surplus native balance is swept to the caller at the end. WETH as ERC20 uses `tokenIn == weth` and allowance.
  function swapAndDeposit(
    SwapAndDepositParams calldata params
  ) external payable nonReentrant whenNotPaused returns (uint256 shares) {
    _pullInputTokens(params.swaps);

    _executeSwaps(params.swaps);

    address[4] memory vaultTokens = params.vault.getTokens();
    uint256[4] memory depositAmounts = _buildDepositAmounts(vaultTokens, params.minDepositAmounts);

    _approveVaultTokens(vaultTokens, depositAmounts, address(params.vault));

    shares = params.vault.deposit(depositAmounts, params.slippageBps, params.minShares);
    require(shares > 0, InsufficientShares());

    _revokeVaultTokenApprovals(vaultTokens, address(params.vault));

    IERC20(address(params.vault)).safeTransfer(_msgSender(), shares);

    _sweepAll(params.sweepTokens, vaultTokens, _msgSender());

    emit SwapAndDeposit(address(params.vault), _msgSender(), shares);
  }

  // ==================== Withdraw Flow ====================

  /// @notice Burn shares, receive vault tokens, execute swaps to desired output, return leftovers.
  function withdrawAndSwap(
    WithdrawAndSwapParams calldata params
  ) external nonReentrant whenNotPaused returns (uint256[4] memory vaultAmounts) {
    IERC20(address(params.vault)).safeTransferFrom(_msgSender(), address(this), params.shares);

    vaultAmounts = params.vault.withdraw(params.shares, params.minWithdrawAmounts, params.unwrapOnWithdraw);

    _executeSwaps(params.swaps);

    address[4] memory vaultTokens = params.vault.getTokens();
    _sweepAll(params.sweepTokens, vaultTokens, _msgSender());

    emit WithdrawAndSwap(address(params.vault), _msgSender(), params.shares);
  }

  // ==================== Internal: Token Handling ====================

  /// @dev Pull ERC20 inputs from `_msgSender()`. Native ETH is used only when `tokenIn == address(0)`:
  ///      `amountIn` for those entries must be covered by `msg.value` (excess ETH is refunded via `_sweepNative`).
  ///      WETH as ERC20 always uses `tokenIn == weth` and `transferFrom`, independent of `msg.value`.
  function _pullInputTokens(SwapParams[] calldata swaps) internal {
    uint256 totalNativeRequired;
    for (uint256 i; i < swaps.length; ) {
      if (swaps[i].tokenIn == address(0)) {
        if (swaps[i].amountIn > 0) {
          totalNativeRequired += swaps[i].amountIn;
        }
      } else if (swaps[i].amountIn > 0) {
        IERC20(swaps[i].tokenIn).safeTransferFrom(_msgSender(), address(this), swaps[i].amountIn);
      }
      unchecked {
        i++;
      }
    }
    if (totalNativeRequired > 0) {
      if (msg.value < totalNativeRequired) revert InsufficientMsgValue();
      IWETH9(weth).deposit{ value: totalNativeRequired }();
    }
  }

  // ==================== Internal: Swap Execution ====================

  /// @dev Execute each swap via the configured swapRouter with opaque calldata.
  ///      Pattern mirrors V3Utils._swap and V4Utils._swap — approve, call, verify delta, reset.
  function _executeSwaps(SwapParams[] calldata swaps) internal {
    for (uint256 i; i < swaps.length; ) {
      if (swaps[i].swapData.length > 0) {
        _executeSingleSwap(swaps[i], i);
      }
      unchecked {
        i++;
      }
    }
  }

  function _executeSingleSwap(SwapParams calldata swap, uint256 index) internal {
    address tokenIn = swap.tokenIn == address(0) ? weth : swap.tokenIn;
    address tokenOut = swap.tokenOut == address(0) ? weth : swap.tokenOut;

    uint256 amountIn = swap.amountIn;
    if (amountIn == 0) {
      amountIn = IERC20(tokenIn).balanceOf(address(this));
    }
    if (amountIn == 0) return;

    uint256 balOutBefore = IERC20(tokenOut).balanceOf(address(this));

    IERC20(tokenIn).safeResetAndApprove(swapRouter, amountIn);

    (bool success, ) = swapRouter.call(swap.swapData);
    if (!success) revert SwapFailed(index);

    IERC20(tokenIn).safeApprove(swapRouter, 0);

    uint256 amountOutDelta = IERC20(tokenOut).balanceOf(address(this)) - balOutBefore;
    if (amountOutDelta < swap.amountOutMin) revert SlippageExceeded(index);
  }

  // ==================== Internal: Deposit Helpers ====================

  /// @dev Use actual gateway balances as `amounts` for `vault.deposit`. `minDepositAmounts[i]` is a
  ///      post-swap slippage floor: revert if balance is below the minimum for that vault token slot.
  function _buildDepositAmounts(
    address[4] memory vaultTokens,
    uint256[4] calldata minDepositAmounts
  ) internal view returns (uint256[4] memory amounts) {
    for (uint256 i; i < 4; ) {
      if (vaultTokens[i] != address(0)) {
        uint256 bal = IERC20(vaultTokens[i]).balanceOf(address(this));
        if (bal < minDepositAmounts[i]) revert InsufficientPostSwapBalance(i);
        amounts[i] = bal;
      }
      unchecked {
        i++;
      }
    }
  }

  function _approveVaultTokens(address[4] memory vaultTokens, uint256[4] memory amounts, address vault) internal {
    for (uint256 i; i < 4; ) {
      if (vaultTokens[i] != address(0) && amounts[i] > 0) {
        IERC20(vaultTokens[i]).safeResetAndApprove(vault, amounts[i]);
      }
      unchecked {
        i++;
      }
    }
  }

  function _revokeVaultTokenApprovals(address[4] memory vaultTokens, address vault) internal {
    for (uint256 i; i < 4; ) {
      if (vaultTokens[i] != address(0)) {
        IERC20(vaultTokens[i]).safeApprove(vault, 0);
      }
      unchecked {
        i++;
      }
    }
  }

  // ==================== Internal: Sweep ====================

  /// @dev Return all remaining balances of sweep tokens + vault tokens to the recipient.
  ///      Also refunds any leftover native ETH.
  function _sweepAll(address[] calldata sweepTokens, address[4] memory vaultTokens, address recipient) internal {
    for (uint256 i; i < sweepTokens.length; ) {
      _sweepToken(sweepTokens[i], recipient);
      unchecked {
        i++;
      }
    }
    for (uint256 i; i < 4; ) {
      if (vaultTokens[i] != address(0)) {
        _sweepToken(vaultTokens[i], recipient);
      }
      unchecked {
        i++;
      }
    }
    _sweepNative(recipient);
  }

  function _sweepToken(address token, address to) internal {
    uint256 bal = IERC20(token).balanceOf(address(this));
    if (bal > 0) {
      IERC20(token).safeTransfer(to, bal);
    }
  }

  function _sweepNative(address to) internal {
    uint256 bal = address(this).balance;
    if (bal > 0) {
      (bool ok, ) = to.call{ value: bal }("");
      if (!ok) revert EthTransferFailed();
    }
  }

  receive() external payable {}
}
