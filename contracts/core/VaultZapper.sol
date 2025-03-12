// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "../interfaces/IWETH9.sol";
import "../interfaces/core/IVaultZapper.sol";
import "../interfaces/core/IWhitelistManager.sol";

contract VaultZapper is AccessControl, IVaultZapper {
  bytes32 public constant ADMIN_ROLE_HASH = keccak256("ADMIN_ROLE");
  bytes32 public constant WITHDRAWER_ROLE_HASH = keccak256("WITHDRAWER_ROLE");
  uint256 public constant Q64 = 2 ** 64;

  IWhitelistManager public whitelistManager;
  address public feeTaker;
  IWETH9 public weth;

  mapping(FeeType => uint64) private _maxFeeX64;

  constructor(address _whitelistManager, address _feeTaker, IWETH9 _weth) {
    require(_whitelistManager != address(0), ZeroAddress());
    require(_feeTaker != address(0), ZeroAddress());
    require(address(_weth) != address(0), ZeroAddress());

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE_HASH, _msgSender());
    _grantRole(WITHDRAWER_ROLE_HASH, _msgSender());

    whitelistManager = IWhitelistManager(_whitelistManager);
    feeTaker = _feeTaker;
    weth = _weth;

    _maxFeeX64[FeeType.GAS_FEE] = 5534023222112865280; // 30%
    _maxFeeX64[FeeType.LIQUIDITY_FEE] = 5534023222112865280; // 30%
    _maxFeeX64[FeeType.PERFORMANCE_FEE] = 3689348814741910528; // 20%
  }

  /// @notice Does 1 or 2 swaps from swapSourceToken to token0 and token1 and adds as much as possible liquidity to an existing vault
  /// @param params Swap and add to vault
  /// Send left-over to recipient
  function swapAndDeposit(SwapAndDepositParams memory params) external payable returns (uint256 shares) {
    uint256 totalIn = 0;

    for (uint256 i = 0; i < params.swaps.length; ) {
      SwapParams memory swap = params.swaps[i];
      require(params.swapSourceToken != swap.swapDestToken, SameToken());

      if (swap.amountIn > 0) {
        totalIn += swap.amountIn;
      }

      unchecked {
        i++;
      }
    }

    require(totalIn >= params.amount, AmountError());

    _prepareSwap(params.swapSourceToken, params.amount, params.swaps);

    if (params.protocolFeeX64 > 0) {
      (uint256 amount, uint256[] memory amounts, , ) = _deductFees(
        DeductFeesParams(
          params.protocolFeeX64,
          FeeType.LIQUIDITY_FEE,
          address(params.vault),
          params.swapSourceToken,
          params.amount,
          params.swaps
        ),
        true
      );

      params.amount = amount;

      for (uint256 i = 0; i < params.swaps.length; ) {
        params.swaps[i].amount = amounts[i];

        unchecked {
          i++;
        }
      }
    }

    (uint256 total0, uint256 total1) = _swapAndPrepareAmounts(
      SwapAndPrepareAmountsParams(params.swapSourceToken, params.amount, params.swaps),
      msg.value != 0
    );

    if (total0 != 0) {
      _safeResetAndApprove(params.token0, address(params.vault), total0);
    }
    if (total1 != 0) {
      _safeResetAndApprove(params.token1, address(params.vault), total1);
    }

    shares = params.vault.deposit(total0, total1, params.amountAddMin0, params.amountAddMin1, msg.sender);
  }

  function withdrawAndSwap(WithdrawAndSwapParams memory params) external override {
    // Implement withdrawAndSwap logic
    require(params.shares > 0, AmountError());
    IERC20(address(params.vault)).transferFrom(msg.sender, address(this), params.shares);

    // (uint256 amount0, uint256 amount1) = params.vault.withdraw(params.shares, address(this), amount0Min, amount1Min);
  }

  // swaps available tokens and prepares max amounts to be added to nfpm
  function _swapAndPrepareAmounts(
    SwapAndPrepareAmountsParams memory params,
    bool unwrap
  ) internal returns (uint256 total, uint256[] memory totals) {
    bool isIncludeSourceToken = false;

    for (uint256 i = 0; i < params.swaps.length; ) {
      SwapParams memory swap = params.swaps[i];

      if (address(params.swapSourceToken) == address(swap.swapDestToken)) {
        isIncludeSourceToken = true;

        if (swap.amount < swap.amountIn) {
          revert AmountError();
        }

        (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
          params.swapSourceToken,
          swap.swapDestToken,
          swap.amountIn,
          swap.amountOutMin,
          swap.swapRouter,
          swap.swapData
        );

        
      }

      unchecked {
        i++;
      }
    }

    // if (params.swapSourceToken == params.token0) {
    //   if (params.amount0 < params.amountIn1) {
    //     revert AmountError();
    //   }
    //   (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
    //     params.token0,
    //     params.token1,
    //     params.amountIn1,
    //     params.amountOut1Min,
    //     params.swapRouter,
    //     params.swapData1
    //   );
    //   total = params.amount0 - amountInDelta;
    //   total1 = params.amount1 + amountOutDelta;
    // } else if (params.swapSourceToken == params.token1) {
    //   if (params.amount1 < params.amountIn0) {
    //     revert AmountError();
    //   }
    //   (uint256 amountInDelta, uint256 amountOutDelta) = _swap(
    //     params.token1,
    //     params.token0,
    //     params.amountIn0,
    //     params.amountOut0Min,
    //     params.swapRouter,
    //     params.swapData0
    //   );
    //   total1 = params.amount1 - amountInDelta;
    //   total = params.amount0 + amountOutDelta;
    // } else if (address(params.swapSourceToken) != address(0)) {
    //   (uint256 amountInDelta0, uint256 amountOutDelta0) = _swap(
    //     params.swapSourceToken,
    //     params.token0,
    //     params.amountIn0,
    //     params.amountOut0Min,
    //     params.swapRouter,
    //     params.swapData0
    //   );
    //   (uint256 amountInDelta1, uint256 amountOutDelta1) = _swap(
    //     params.swapSourceToken,
    //     params.token1,
    //     params.amountIn1,
    //     params.amountOut1Min,
    //     params.swapRouter,
    //     params.swapData1
    //   );
    //   total = params.amount0 + amountOutDelta0;
    //   total1 = params.amount1 + amountOutDelta1;

    //   if (params.amount2 < amountInDelta0 + amountInDelta1) {
    //     revert AmountError();
    //   }
    //   // return third token leftover if any
    //   uint256 leftOver = params.amount2 - amountInDelta0 - amountInDelta1;

    //   if (leftOver != 0) {
    //     _transferToken(params.recipient, params.swapSourceToken, leftOver, unwrap);
    //   }
    // } else {
    //   total = params.amount0;
    //   total1 = params.amount1;
    // }
  }

  // general swap function which uses external router with off-chain calculated swap instructions
  // does slippage check with amountOutMin param
  // returns token amounts deltas after swap
  function _swap(
    IERC20 tokenIn,
    IERC20 tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address swapRouter,
    bytes memory swapData
  ) internal returns (uint256 amountInDelta, uint256 amountOutDelta) {
    require(whitelistManager.isWhitelistedSwapRouter(swapRouter), InvalidSwapRouter());

    if (amountIn != 0 && swapData.length != 0 && address(tokenOut) != address(0)) {
      uint256 balanceInBefore = tokenIn.balanceOf(address(this));
      uint256 balanceOutBefore = tokenOut.balanceOf(address(this));

      // approve needed amount
      _safeApprove(tokenIn, swapRouter, amountIn);
      // execute swap
      (bool success, bytes memory data) = swapRouter.call(swapData);
      if (!success) {
        assembly {
          revert(add(32, data), mload(data))
        }
      }

      // reset approval
      _safeApprove(tokenIn, swapRouter, 0);

      uint256 balanceInAfter = tokenIn.balanceOf(address(this));
      uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

      amountInDelta = balanceInBefore - balanceInAfter;
      amountOutDelta = balanceOutAfter - balanceOutBefore;

      // amountMin slippage check
      if (amountOutDelta < amountOutMin) {
        revert SlippageError();
      }

      // event for any swap with exact swapped value
      emit Swap(address(tokenIn), address(tokenOut), amountInDelta, amountOutDelta);
    }
  }

  /// @dev some tokens require allowance == 0 to approve new amount
  /// but some tokens does not allow approve amount = 0
  /// we try to set allowance = 0 before approve new amount. if it revert means that
  /// the token not allow to approve 0, which means the following line code will work properly
  function _safeResetAndApprove(IERC20 token, address _spender, uint256 _value) internal {
    /// @dev omitted approve(0) result because it might fail and does not break the flow
    (bool success, ) = address(token).call(abi.encodeWithSelector(token.approve.selector, _spender, 0));
    require(success, ResetApproveFailed());

    /// @dev value for approval after reset must greater than 0
    require(_value > 0, InvalidApproval());
    _safeApprove(token, _spender, _value);
  }

  function _safeApprove(IERC20 token, address _spender, uint256 _value) internal {
    (bool success, bytes memory returnData) = address(token).call(
      abi.encodeWithSelector(token.approve.selector, _spender, _value)
    );
    if (_value == 0) {
      // some token does not allow approve(0) so we skip check for this case
      return;
    }
    require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), "SafeERC20: approve failed");
  }

  // transfers token (or unwraps WETH and sends ETH)
  function _transferToken(address to, IERC20 token, uint256 amount, bool unwrap) internal {
    if (address(weth) == address(token) && unwrap) {
      weth.withdraw(amount);
      (bool sent, ) = to.call{ value: amount }("");
      if (!sent) {
        revert EtherSendFailed();
      }
    } else {
      SafeERC20.safeTransfer(token, to, amount);
    }
  }

  // @dev checks if required amounts are provided and are exact - wraps any provided ETH as WETH
  // @notice if less or more provided reverts
  function _prepareSwap(IERC20 swapSourceToken, uint256 amount, SwapParams[] memory swaps) internal {
    uint256[] memory amountAdded;
    uint256 amountSourceAdded;

    bool isSwapTokensIncludedWeth = true;
    bool isIncludedSourceToken = false;

    // wrap ether sent
    if (msg.value != 0) {
      weth.deposit{ value: msg.value }();

      for (uint256 i = 0; i < swaps.length; ) {
        SwapParams memory swap = swaps[i];

        if (address(weth) == address(swap.swapDestToken)) {
          amountAdded.push(msg.value);
          if (amountAdded[i] > swap.amount) {
            revert TooMuchEtherSent();
          }
        } else {
          if (i == swaps.length - 1) {
            isSwapTokensIncludedWeth = false;
          }
        }

        unchecked {
          i++;
        }
      }

      if (!isSwapTokensIncludedWeth) {
        if (address(weth) == address(swapSourceToken)) {
          amountSourceAdded = msg.value;
          if (amountSourceAdded > amount) {
            revert TooMuchEtherSent();
          }
        } else {
          revert NoEtherToken();
        }
      }
    }

    // get missing tokens (fails if not enough provided)
    for (uint256 i = 0; i < swaps.length; ) {
      SwapParams memory swap = swaps[i];

      if (address(swapSourceToken) == address(swap.swapDestToken)) {
        isIncludedSourceToken = true;
      }

      if (swap.amount > amountAdded[i]) {
        uint256 balanceBefore = swap.swapDestToken.balanceOf(address(this));
        SafeERC20.safeTransferFrom(swap.swapDestToken, msg.sender, address(this), swap.amount - amountAdded[i]);
        uint256 balanceAfter = swap.swapDestToken.balanceOf(address(this));

        if (balanceAfter - balanceBefore != swap.amount - amountAdded[i]) {
          revert TransferError();
        }
      }

      unchecked {
        i++;
      }
    }

    if (amount > amountSourceAdded && address(swapSourceToken) != address(0) && !isIncludedSourceToken) {
      uint256 balanceBefore = swapSourceToken.balanceOf(address(this));
      SafeERC20.safeTransferFrom(swapSourceToken, msg.sender, address(this), amount - amountSourceAdded);
      uint256 balanceAfter = swapSourceToken.balanceOf(address(this));

      if (balanceAfter - balanceBefore != amount - amountSourceAdded) {
        revert TransferError();
      }
    }
  }

  /**
   * @notice calculate fee
   * @param emitEvent: whether to emit event or not. Since swap and mint have not had token id yet.
   * we need to emit event latter
   */
  function _deductFees(
    DeductFeesParams memory params,
    bool emitEvent
  )
    internal
    returns (uint256 amountLeft, uint256[] memory amountsLeft, uint256 feeAmount, uint256[] memory feeAmounts)
  {
    if (params.feeX64 > _maxFeeX64[params.feeType]) {
      revert TooMuchFee();
    }

    // to save gas, we always need to check if fee exists before deductFees
    if (params.feeX64 == 0) {
      revert NoFees();
    }

    if (params.amount > 0) {
      feeAmount = FullMath.mulDiv(params.amount, params.feeX64, Q64);
      amountLeft = params.amount - feeAmount;
      if (feeAmount > 0) {
        SafeERC20.safeTransfer(params.swapSourceToken, feeTaker, feeAmount);
      }
    }

    for (uint256 i = 0; i < params.swaps.length; ) {
      SwapParams memory swap = params.swaps[i];

      if (swap.amount > 0) {
        feeAmounts[i] = FullMath.mulDiv(swap.amount, params.feeX64, Q64);
        amountsLeft[i] = swap.amount - feeAmounts[i];
        if (feeAmounts[i] > 0) {
          SafeERC20.safeTransfer(swap.swapDestToken, feeTaker, feeAmounts[i]);
        }
      }
      unchecked {
        i++;
      }
    }

    if (emitEvent) {
      emit VaultDeductFees(
        params.vault,
        DeductFeesEventData(
          params.swapSourceToken,
          params.amount,
          feeAmount,
          params.swaps,
          amountsLeft,
          feeAmounts,
          params.feeX64,
          params.feeType
        )
      );
    }
  }

  // returns leftover token balances
  function _returnLeftoverTokens(ReturnLeftoverTokensParams memory params) internal {
    uint256 left0 = params.total0 - params.added0;
    uint256 left1 = params.total1 - params.added1;

    // return leftovers
    if (left0 != 0) {
      _transferToken(params.to, params.token0, left0, params.unwrap);
    }
    if (left1 != 0) {
      _transferToken(params.to, params.token1, left1, params.unwrap);
    }
  }

  /// @notice Set the whitelist manager address
  /// @param _whitelistManager The address of the whitelist manager
  function setWhitelistManager(address _whitelistManager) external override onlyRole(ADMIN_ROLE_HASH) {
    require(_whitelistManager != address(0), ZeroAddress());
    whitelistManager = IWhitelistManager(_whitelistManager);
  }

  /// @notice Set the fee taker address
  /// @param _feeTaker The address of the fee taker
  function setFeeTaker(address _feeTaker) external override onlyRole(ADMIN_ROLE_HASH) {
    require(_feeTaker != address(0), ZeroAddress());
    feeTaker = _feeTaker;
  }
}
