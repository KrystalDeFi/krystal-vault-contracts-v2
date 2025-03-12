// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../ICommon.sol";
import "./IVault.sol";

interface IVaultZapper is ICommon {
  enum FeeType {
    GAS_FEE,
    LIQUIDITY_FEE,
    PERFORMANCE_FEE
  }

  struct SwapParams {
    address swapRouter;
    IERC20 swapDestToken;
    uint256 amount;
    uint256 amountIn;
    uint256 amountOutMin;
    address recipient;
    uint256 deadline;
    bytes swapData;
  }

  struct SwapAndDepositParams {
    IVault vault;
    uint64 protocolFeeX64;
    IERC20 swapSourceToken;
    uint256 amount;
    SwapParams[] swaps;
  }

  struct WithdrawAndSwapParams {
    IVault vault;
    uint256 shares;
    address to;
    uint256 amount0Min;
    uint256 amount1Min;
    bytes swapData;
  }

  struct SwapAndPrepareAmountsParams {
    IERC20 swapSourceToken;
    uint256 amount;
    SwapParams[] swaps;
  }

  struct ReturnLeftoverTokensParams {
    address to;
    IERC20 token0;
    IERC20 token1;
    uint256 total0;
    uint256 total1;
    uint256 added0;
    uint256 added1;
    bool unwrap;
  }

  struct DeductFeesParams {
    uint64 feeX64;
    FeeType feeType;
    address vault;
    IERC20 swapSourceToken;
    uint256 amount;
    SwapParams[] swaps;
  }

  struct DeductFeesEventData {
    IERC20 swapSourceToken;
    uint256 amount;
    uint256 feeAmount;
    SwapParams[] swaps;
    uint256[] amountsLeft;
    uint256[] feeAmounts;
    uint64 feeX64;
    FeeType feeType;
  }

  error AmountError();

  error SlippageError();

  error EtherSendFailed();

  error TransferError();

  error ResetApproveFailed();

  error NoEtherToken();

  error TooMuchEtherSent();

  error TooMuchFee();

  error NoFees();

  error SameToken();

  error InvalidApproval();

  event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

  event VaultDeductFees(address indexed vault, DeductFeesEventData data);

  function swapAndDeposit(SwapAndDepositParams memory params) external payable returns (uint256 shares);

  function withdrawAndSwap(WithdrawAndSwapParams memory params) external;

  function setWhitelistManager(address _whitelistManager) external;

  function setFeeTaker(address _feeTaker) external;
}
