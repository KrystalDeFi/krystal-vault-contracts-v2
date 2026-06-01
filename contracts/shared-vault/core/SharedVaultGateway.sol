// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { SafeApprovalLib } from "../../private-vault/libraries/SafeApprovalLib.sol";
import { Withdrawable } from "../../common/Withdrawable.sol";
import "../interfaces/ISharedVault.sol";
import "../../public-vault/interfaces/IWETH9.sol";

/// @title SharedVaultGateway
/// @notice Simplifies deposits into and withdrawals from SharedVault by accepting arbitrary
///         input tokens and executing pre-built swap calldata (from an off-chain aggregator API)
///         to convert them into the vault's required proportional token mix.
///
/// Deposit flow:  user sends any tokens → gateway swaps to vault tokens → deposits to vault → returns shares + leftovers
/// Withdraw flow: user burns shares via gateway → receives vault tokens → gateway swaps to desired output → returns output + leftovers
contract SharedVaultGateway is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, Withdrawable {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  // ==================== Errors ====================

  error ZeroAddress();
  error SwapFailed(uint256 index);
  error SlippageExceeded(uint256 index);
  error InsufficientShares();
  error InvalidSwapRouter();
  error InsufficientPostSwapBalance(uint256 tokenIndex);
  error EthTransferFailed();
  error InsufficientWithdrawBalance(uint256 swapIndex);

  // ==================== Events ====================

  event SwapAndDeposit(address indexed vault, address indexed depositor, uint256 sharesReceived);

  event WithdrawAndSwap(address indexed vault, address indexed withdrawer, uint256 sharesBurned);

  event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);

  // ==================== Structs ====================

  /// @param tokenIn  ERC20 source token for the swap. Must already be held by the gateway
  ///                 (pulled via `inputs[]` in the deposit flow, or received from `vault.withdraw()`
  ///                 in the withdraw flow). Always a real token address — never `address(0)`.
  /// @param amountIn Portion of the gateway's `tokenIn` balance to swap. `0` = swap the full balance.
  /// @param tokenOut ERC20 the swap produces. Always a real token address — never `address(0)`.
  struct SwapParams {
    address tokenIn;
    uint256 amountIn; // 0 = swap full balance of tokenIn held by gateway
    address tokenOut;
    uint256 amountOutMin;
    bytes swapData; // calldata for swapRouter; empty = skip only when amountOutMin == 0
  }

  /// @notice A total token amount to pull from the caller upfront. The gateway holds the
  ///         pulled balance for the rest of the call; swaps[] then optionally consume portions
  ///         to produce vault tokens, and any remaining balance is deposited directly.
  struct InputToken {
    address token;
    uint256 amount;
  }

  struct SwapAndDepositParams {
    ISharedVault vault;
    /// @notice Total amounts pulled from the caller upfront. List each input token exactly once
    ///         with the cumulative amount the gateway needs (e.g. 10 USDC, of which 2 will be
    ///         swapped to WETH and 8 deposited directly).
    ///         For native ETH input, send `msg.value`; the gateway wraps it to WETH and any
    ///         inputs[] entry for WETH is skipped (the wrapped balance is the WETH supply).
    InputToken[] inputs;
    SwapParams[] swaps;
    /// @notice Per vault-token slot: minimum balance the gateway must hold after swaps (slippage floor).
    ///         If actual balance is below this for a configured vault token, the call reverts before `deposit`.
    ///         Pass 0 to skip the check for that slot. Actual amounts sent to the vault are always the
    ///         gateway's current ERC20 balances (never inflated above balance).
    uint256[4] minDepositAmounts;
    uint16 slippageBps;
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

  /// @notice Pull input tokens upfront, execute swaps from gateway balance to produce vault tokens,
  ///         deposit proportionally, return leftovers.
  /// @dev Swap calldata is built off-chain by the Krystal API swap aggregator.
  ///      The gateway briefly holds tokens during the tx; nothing persists across calls.
  ///      **Flow**: `inputs[]` declares the *total* amounts pulled from the caller (e.g. 10 USDC).
  ///      `swaps[]` then specifies how portions of those balances are converted (e.g. swap 2 USDC → WETH).
  ///      Whatever is not consumed by swaps remains in the gateway and is deposited directly to the vault
  ///      (e.g. the remaining 8 USDC). Any post-deposit residue is swept back to the caller.
  ///      **Native ETH**: if `msg.value > 0` it is wrapped to WETH before any swap runs, so the swap
  ///      router only ever sees WETH. Swap entries that consume this WETH use `tokenIn == weth` with
  ///      `amountIn == 0` (full balance) or a specific sub-amount. Any WETH that remains after swaps
  ///      and deposit is unwrapped back to ETH and returned to the caller.
  ///      **Swap skips**: `swapData.length == 0` means "skip this entry" only when `amountOutMin == 0`.
  ///      A nonzero `amountOutMin` is treated as a hard per-swap slippage floor and reverts if no swap runs.
  function swapAndDeposit(
    SwapAndDepositParams calldata params
  ) external payable nonReentrant whenNotPaused returns (uint256 shares) {
    bool nativeWrapped = _pullInputTokens(params.inputs);

    _executeSwaps(params.swaps);

    address[4] memory vaultTokens = params.vault.getTokens();
    uint256[4] memory depositAmounts = _buildDepositAmounts(vaultTokens, params.minDepositAmounts);

    _approveVaultTokens(vaultTokens, depositAmounts, address(params.vault));

    shares = params.vault.deposit(depositAmounts, params.slippageBps, _msgSender());
    require(shares > 0, InsufficientShares());

    _revokeVaultTokenApprovals(vaultTokens, address(params.vault));

    _sweepAll(params.sweepTokens, vaultTokens, _msgSender(), nativeWrapped);

    // Sweep any non-vault input token leftovers not already caught above.
    // This handles partial-fill swaps on intermediate tokens not listed in sweepTokens.
    // _sweepToken is idempotent (no-op on zero balance), so double-sweeping is safe.
    for (uint256 i; i < params.inputs.length; ) {
      _sweepToken(params.inputs[i].token, _msgSender());
      unchecked {
        i++;
      }
    }

    emit SwapAndDeposit(address(params.vault), _msgSender(), shares);
  }

  // ==================== Withdraw Flow ====================

  /// @notice Burn shares, receive vault tokens, execute swaps to desired output, return leftovers.
  /// @dev Swap entries with empty `swapData` are skipped only when `amountOutMin == 0`. A nonzero
  ///      `amountOutMin` is enforced even when the resolved full-balance `amountIn` is zero.
  function withdrawAndSwap(
    WithdrawAndSwapParams calldata params
  ) external nonReentrant whenNotPaused returns (uint256[4] memory vaultAmounts) {
    // Always withdraw as WETH (unwrap=false); the gateway handles unwrapping below if requested.
    vaultAmounts = params.vault.withdraw(params.shares, params.minWithdrawAmounts, false, _msgSender());

    _executeSwaps(params.swaps);

    address[4] memory vaultTokens = params.vault.getTokens();
    _sweepAll(params.sweepTokens, vaultTokens, _msgSender(), params.unwrapOnWithdraw);

    emit WithdrawAndSwap(address(params.vault), _msgSender(), params.shares);
  }

  // ==================== Internal: Token Handling ====================

  /// @dev Wrap any native ETH to WETH first, then pull each declared input token in full from the caller.
  ///      `token` must always be a real ERC20 address — `address(0)` is never valid here.
  ///
  ///      There is exactly **one** WETH source per call:
  ///      - Native ETH path  (`msg.value > 0`): the full `msg.value` is wrapped to WETH.
  ///        Any inputs[] entry with `token == weth` is skipped (the wrapped balance is the WETH input).
  ///      - ERC20 WETH path (`msg.value == 0`): WETH is pulled from the caller's wallet via
  ///        `transferFrom` for entries where `token == weth && amount > 0`.
  ///
  ///      Other non-WETH ERC20 tokens are always pulled via `transferFrom` regardless of path.
  /// @return nativeWrapped True when `msg.value > 0`; tells `_sweepAll` to unwrap any residual
  ///         WETH and return it as native ETH.
  function _pullInputTokens(InputToken[] calldata inputs) internal returns (bool nativeWrapped) {
    if (msg.value > 0) {
      nativeWrapped = true;
      IWETH9(weth).deposit{ value: msg.value }();
    }
    for (uint256 i; i < inputs.length; ) {
      require(inputs[i].token != address(0), ZeroAddress());
      // Skip transferFrom for WETH when native ETH was provided — the wrap already covers it.
      if (inputs[i].amount > 0 && !(nativeWrapped && inputs[i].token == weth)) {
        IERC20(inputs[i].token).safeTransferFrom(_msgSender(), address(this), inputs[i].amount);
      }
      unchecked {
        i++;
      }
    }
  }

  // ==================== Internal: Swap Execution ====================

  /// @dev Execute each swap via the configured swapRouter with opaque calldata.
  ///      Pattern mirrors V3Utils._swap and V4Utils._swap — approve, call, verify delta, reset.
  function _executeSwaps(SwapParams[] calldata swaps) internal {
    for (uint256 i; i < swaps.length; ) {
      if (swaps[i].swapData.length == 0) {
        if (swaps[i].amountOutMin != 0) revert SlippageExceeded(i);
      } else {
        _executeSingleSwap(swaps[i], i);
      }
      unchecked {
        i++;
      }
    }
  }

  function _executeSingleSwap(SwapParams calldata swap, uint256 index) internal {
    address tokenIn = swap.tokenIn;
    address tokenOut = swap.tokenOut;

    uint256 amountIn = swap.amountIn;
    if (amountIn == 0) {
      amountIn = IERC20(tokenIn).balanceOf(address(this));
    }
    if (amountIn == 0) {
      if (swap.amountOutMin != 0) revert SlippageExceeded(index);
      return;
    }

    // Per-swap balance check: runs just before execution so that tokens produced by
    // earlier swaps in the same batch are already available (multi-hop chains).
    if (swap.amountIn > 0 && IERC20(tokenIn).balanceOf(address(this)) < amountIn) {
      revert InsufficientWithdrawBalance(index);
    }

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
  ///      If `unwrapWeth` is true (native ETH was wrapped on the way in), any WETH still held by the
  ///      gateway after token sweeps is unwrapped to ETH so the caller receives native ETH, not WETH.
  ///      Also refunds any leftover native ETH.
  function _sweepAll(
    address[] calldata sweepTokens,
    address[4] memory vaultTokens,
    address recipient,
    bool unwrapWeth
  ) internal {
    for (uint256 i; i < sweepTokens.length; ) {
      // Skip WETH here when unwrapping — it will be handled as native ETH below.
      if (!(unwrapWeth && sweepTokens[i] == weth)) {
        _sweepToken(sweepTokens[i], recipient);
      }
      unchecked {
        i++;
      }
    }
    for (uint256 i; i < 4; ) {
      // Skip WETH here when unwrapping — it will be handled as native ETH below.
      if (vaultTokens[i] != address(0) && !(unwrapWeth && vaultTokens[i] == weth)) {
        _sweepToken(vaultTokens[i], recipient);
      }
      unchecked {
        i++;
      }
    }
    if (unwrapWeth) {
      uint256 wethBal = IERC20(weth).balanceOf(address(this));
      if (wethBal > 0) IWETH9(weth).withdraw(wethBal);
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

  /// @inheritdoc Withdrawable
  function _checkWithdrawPermission() internal view override {
    _checkOwner();
  }

  receive() external payable {}
}
