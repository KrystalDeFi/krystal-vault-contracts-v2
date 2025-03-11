// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IWETH9.sol";
import "../ICommon.sol";
import "./IVault.sol";

interface IVaultZapper is ICommon {
  enum FeeType {
    GAS_FEE,
    LIQUIDITY_FEE,
    PERFORMANCE_FEE
  }

  enum Protocol {
    UNI_V3,
    ALGEBRA_V1
  }

  struct SwapAndDepositParams {
    Protocol protocol;
    IVault vault;
    address swapRouter;
    uint256 amount0;
    uint256 amount1;
    uint256 amount2;
    address recipient;
    uint256 deadline;
    IERC20 swapSourceToken;
    uint256 amountIn0;
    uint256 amountOut0Min;
    bytes swapData0;
    uint256 amountIn1;
    uint256 amountOut1Min;
    bytes swapData1;
    uint256 amountAddMin0;
    uint256 amountAddMin1;
    uint64 protocolFeeX64;
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
    IWETH9 weth;
    IERC20 token0;
    IERC20 token1;
    address swapRouter;
    uint256 amount0;
    uint256 amount1;
    uint256 amount2;
    address recipient;
    uint256 deadline;
    IERC20 swapSourceToken;
    uint256 amountIn0;
    uint256 amountOut0Min;
    bytes swapData0;
    uint256 amountIn1;
    uint256 amountOut1Min;
    bytes swapData1;
  }

  struct ReturnLeftoverTokensParams {
    IWETH9 weth;
    address to;
    IERC20 token0;
    IERC20 token1;
    uint256 total0;
    uint256 total1;
    uint256 added0;
    uint256 added1;
    bool unwrap;
  }

  error AmountError();

  error SlippageError();

  error EtherSendFailed();

  error NotSupportedProtocol();

  error TransferError();

  error ResetApproveFailed();

  error NoEtherToken();

  error TooMuchEtherSent();

  error TooMuchFee();

  error NoFees();

  error SameToken();

  error InvalidApproval();

  function swapAndDeposit(SwapAndDepositParams memory params) external payable returns (uint256 shares);

  function withdrawAndSwap(WithdrawAndSwapParams memory params) external;

  function setWhitelistManager(address _whitelistManager) external;

  function setFeeTaker(address _feeTaker) external;
}
