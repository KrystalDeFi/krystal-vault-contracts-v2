// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/core/IConfigManager.sol";
import "../../interfaces/core/IOptimalSwapper.sol";
import "../../libraries/SafeApprovalLib.sol";
import "../../interfaces/strategies/aerodrome/ICLPool.sol";
import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

/**
 * @title RewardSwapper
 * @notice Contract for swapping farming reward tokens to principal tokens
 * @dev Manages reward token to pool mappings and handles swaps
 */
contract RewardSwapper is Ownable {
  using SafeERC20 for IERC20;
  using SafeApprovalLib for IERC20;

  uint256 internal constant Q96 = 0x1000000000000000000000000;
  uint256 internal constant Q192 = 0x1000000000000000000000000000000000000000000000000;

  // State variables
  IConfigManager public immutable configManager;
  IOptimalSwapper public immutable poolSwapper;

  // Nested mapping from reward token to principal token to pool address for swapping
  mapping(address => mapping(address => address)) public rewardTokenPools;

  // Mapping from reward token to whether it's supported
  mapping(address => bool) public supportedRewardTokens;

  // Events
  event RewardTokenPoolSet(address indexed rewardToken, address indexed principalToken, address indexed pool);
  event RewardTokenSupported(address indexed rewardToken, bool supported);
  event RewardSwapped(
    address indexed rewardToken,
    address indexed principalToken,
    uint256 amountIn,
    uint256 amountOut,
    address indexed pool
  );

  // Errors
  error UnsupportedRewardToken();
  error NoPoolConfigured();
  error InvalidPool();
  error SwapFailed();
  error InsufficientAmountOut();

  /**
   * @notice Constructor
   * @param _configManager Address of the config manager
   * @param _poolSwapper Address of the pool swapper
   * @param _owner Address of the contract owner
   */
  constructor(address _configManager, address _poolSwapper, address _owner) Ownable(_owner) {
    require(_configManager != address(0), "ZeroAddress");
    require(_poolSwapper != address(0), "ZeroAddress");
    configManager = IConfigManager(_configManager);
    poolSwapper = IOptimalSwapper(_poolSwapper);
  }

  /**
   * @notice Set the pool for a reward token and principal token pair
   * @param rewardToken Address of the reward token
   * @param principalToken Address of the principal token
   * @param pool Address of the pool to swap through
   */
  function setRewardTokenPool(address rewardToken, address principalToken, address pool) external onlyOwner {
    require(rewardToken != address(0), "ZeroAddress");
    require(principalToken != address(0), "ZeroAddress");

    rewardTokenPools[rewardToken][principalToken] = pool;
    emit RewardTokenPoolSet(rewardToken, principalToken, pool);
  }

  /**
   * @notice Set whether a reward token is supported
   * @param rewardToken Address of the reward token
   * @param supported Whether the token is supported
   */
  function setSupportedRewardToken(address rewardToken, bool supported) external onlyOwner {
    require(rewardToken != address(0), "ZeroAddress");

    supportedRewardTokens[rewardToken] = supported;
    emit RewardTokenSupported(rewardToken, supported);
  }

  /**
   * @notice Swap reward token to principal token
   * @param rewardToken Address of the reward token to swap
   * @param principalToken Address of the principal token to swap to
   * @param amountIn Amount of reward token to swap
   * @param amountOutMin Minimum amount of principal token expected
   * @param swapData Additional data for the swap (router-specific)
   * @return amountOut Amount of principal token received
   */
  function swapRewardToPrincipal(
    address rewardToken,
    address principalToken,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes calldata swapData
  ) external returns (uint256 amountOut) {
    require(rewardToken != principalToken, "SameToken");
    require(supportedRewardTokens[rewardToken], UnsupportedRewardToken());

    address pool = rewardTokenPools[rewardToken][principalToken];
    require(pool != address(0), NoPoolConfigured());

    // Transfer reward tokens from caller
    IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amountIn);

    uint256 balanceBefore = IERC20(principalToken).balanceOf(address(this));

    // Execute swap through the configured pool
    // This is a simplified implementation - in practice, you'd integrate with specific DEX routers
    _executeSwap(rewardToken, principalToken, amountIn, pool, swapData);

    uint256 balanceAfter = IERC20(principalToken).balanceOf(address(this));
    amountOut = balanceAfter - balanceBefore;

    require(amountOut >= amountOutMin, InsufficientAmountOut());

    // Transfer principal tokens back to caller
    IERC20(principalToken).safeTransfer(msg.sender, amountOut);

    emit RewardSwapped(rewardToken, principalToken, amountIn, amountOut, pool);
  }

  /**
   * @notice Get the estimated output amount for swapping reward token to principal token
   * @param rewardToken Address of the reward token
   * @param principalToken Address of the principal token
   * @param amountIn Amount of reward token to swap
   * @return amountOut Estimated amount of principal token
   */
  function getAmountOut(address rewardToken, address principalToken, uint256 amountIn)
    public
    view
    returns (uint256 amountOut)
  {
    if (rewardToken == principalToken) return amountIn;

    require(supportedRewardTokens[rewardToken], UnsupportedRewardToken());

    address pool = rewardTokenPools[rewardToken][principalToken];
    require(pool != address(0), NoPoolConfigured());

    return _getQuote(pool, rewardToken, principalToken, amountIn);
  }

  /**
   * @notice Check if a reward token to principal token swap is supported
   * @param rewardToken Address of the reward token
   * @param principalToken Address of the principal token
   * @return supported True if the swap pair is supported
   */
  function isSwapSupported(address rewardToken, address principalToken) external view returns (bool supported) {
    return rewardTokenPools[rewardToken][principalToken] != address(0) && supportedRewardTokens[rewardToken];
  }

  /**
   * @notice Get the pool address for a reward-principal token pair
   * @param rewardToken Address of the reward token
   * @param principalToken Address of the principal token
   * @return pool Address of the pool for this pair
   */
  function getPoolForPair(address rewardToken, address principalToken) external view returns (address pool) {
    return rewardTokenPools[rewardToken][principalToken];
  }

  /**
   * @notice Get the value of reward token in terms of principal token
   * @param rewardToken Address of the reward token
   * @param principalToken Address of the principal token
   * @param amount Amount of reward token
   * @return value Value in terms of principal token
   */
  function getRewardValue(address rewardToken, address principalToken, uint256 amount)
    external
    view
    returns (uint256 value)
  {
    return getAmountOut(rewardToken, principalToken, amount);
  }

  /**
   * @notice Get quote for token swap through pool
   * @param pool Address of the Uniswap V3 pool
   * @param tokenIn Address of input token
   * @param tokenOut Address of output token
   * @param amountIn Amount of input token
   * @return amountOut Estimated amount of output token
   */
  function _getQuote(address pool, address tokenIn, address tokenOut, uint256 amountIn)
    internal
    view
    returns (uint256 amountOut)
  {
    if (amountIn == 0) return 0;

    // Get pool information
    address token0 = ICLPool(pool).token0();
    address token1 = ICLPool(pool).token1();

    // Verify the pool contains both tokens
    require((tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0), InvalidPool());

    // Get current pool state
    (uint160 sqrtPriceX96,,,,,) = ICLPool(pool).slot0();
    uint128 liquidity = ICLPool(pool).liquidity();

    // If no liquidity, return 0
    if (liquidity == 0) return 0;

    // Simple approximation: use current price with a basic calculation
    // This is a simplified approach and doesn't account for slippage or complex math
    uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

    if (tokenIn != token0) priceX96 = Q192 / priceX96;
    amountOut = FullMath.mulDiv(amountIn, priceX96, Q96);
  }

  /**
   * @notice Execute swap through the configured pool
   * @param tokenIn Address of input token
   * @param tokenOut Address of output token
   * @param amountIn Amount of input token
   * @param pool Address of the pool
   * @param swapData Additional swap data
   */
  function _executeSwap(address tokenIn, address tokenOut, uint256 amountIn, address pool, bytes calldata swapData)
    internal
  {
    // Decode minimum amount out from swapData
    uint256 amountOutMin = swapData.length >= 32 ? abi.decode(swapData, (uint256)) : 0;

    // Determine swap direction by comparing token addresses
    address token0 = ICLPool(pool).token0();
    address token1 = ICLPool(pool).token1();

    bool zeroForOne;
    if (tokenIn == token0 && tokenOut == token1) zeroForOne = true;
    else if (tokenIn == token1 && tokenOut == token0) zeroForOne = false;
    else revert InvalidPool();

    // Approve tokens to pool swapper using safe reset-and-approve pattern
    IERC20(tokenIn).safeResetAndApprove(address(poolSwapper), amountIn);

    // Execute swap through PoolOptimalSwapper
    (uint256 amountOut,) = poolSwapper.poolSwap(pool, amountIn, zeroForOne, amountOutMin, "");

    // Reset approval to 0 for security
    IERC20(tokenIn).safeApprove(address(poolSwapper), 0);

    // Verify we got some output
    require(amountOut > 0, SwapFailed());
  }

  /**
   * @notice Emergency function to recover tokens
   * @param token Address of the token to recover
   * @param amount Amount to recover
   * @param recipient Address to send recovered tokens to
   */
  function emergencyRecover(address token, uint256 amount, address recipient) external onlyOwner {
    require(recipient != address(0), "ZeroAddress");
    IERC20(token).safeTransfer(recipient, amount);
  }
}
