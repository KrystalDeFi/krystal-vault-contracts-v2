// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon, USER, WETH, USDC } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedAerodromeStrategy } from "../../contracts/shared-vault/strategies/SharedAerodromeStrategy.sol";
import { SharedStrategyBeacon } from "../../contracts/shared-vault/strategies/SharedStrategyBeacon.sol";
import { SharedStrategyProxy } from "../../contracts/shared-vault/strategies/SharedStrategyProxy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { INonfungiblePositionManager as INFPM } from
  "../../contracts/common/interfaces/protocols/aerodrome/INonfungiblePositionManager.sol";

interface IAeroSwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    int24 tickSpacing;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @notice SharedAerodromeStrategy against Aero (the merged Aerodrome + Velodrome, MetaDEX Slipstream) on a Base
///         fork after its 2026-10-21 launch. The strategy is unchanged: the Aero NFPM and pools keep the Slipstream
///         ABI, so whitelisting the Aero NFPM on the ConfigManager is all it takes.
contract SharedVaultAeroIntegrationTest is TestCommon {
  uint256 constant AERO_FORK_BLOCK = 52_900_000;

  address constant AERO_NFPM = 0x4857DB576eE0e45F10525eC59527BfD10beeC60b;
  address constant AERO_SWAP_ROUTER = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;

  // Aero CL WETH/USDC pool, tickSpacing 100; empty at the fork block, so the vault's position is its only liquidity
  uint8 constant PROTOCOL = 3;
  int24 constant TICK_SPACING = 100;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;

  SharedConfigManager configManager;
  SharedVaultFactory vaultFactory;
  SharedAerodromeStrategy aeroStrategy;
  SharedStrategyBeacon aeroBeacon;
  SharedStrategyProxy aeroProxy;
  SharedVault vault;

  address vaultOwner = USER;
  address feeRecipient = makeAddr("feeRecipient");

  function setUp() public {
    vm.selectFork(vm.createFork(vm.envString("RPC_URL"), AERO_FORK_BLOCK));

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);

    vm.startPrank(vaultOwner);

    address[] memory nfpms = new address[](1);
    nfpms[0] = AERO_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      vaultOwner, new address[](0), new address[](0), feeRecipient, 0, nfpms, new address[](0), new address[](0)
    );

    // The swap router is never reached here: every operation below passes no swap data.
    aeroStrategy = new SharedAerodromeStrategy(AERO_SWAP_ROUTER);
    aeroBeacon = new SharedStrategyBeacon(address(aeroStrategy), vaultOwner);
    aeroProxy = new SharedStrategyProxy(address(aeroBeacon));

    address[] memory targets = new address[](1);
    targets[0] = address(aeroProxy);
    configManager.setWhitelistTargets(targets, true);

    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(new SharedVault()), WETH);

    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);
    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-Aero", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------------------------

  function _execute(bytes memory data) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(aeroProxy), data, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _mint() internal returns (uint256 tokenId) {
    _execute(_swapAndMintData(0.5 ether, 1500e6));
    tokenId = IERC721Enumerable(AERO_NFPM).tokenOfOwnerByIndex(address(vault), 0);
  }

  function _liquidity(uint256 tokenId) internal view returns (uint128 liquidity) {
    (,,,,,,, liquidity,,,,) = INFPM(AERO_NFPM).positions(tokenId);
  }

  function _swapAndMintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: PROTOCOL,
      nfpm: AERO_NFPM,
      token0: WETH,
      token1: USDC,
      fee: 0,
      tickSpacing: TICK_SPACING,
      tickLower: TICK_LOWER,
      tickUpper: TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: amount0,
      amount1: amount1,
      amount2: 0,
      recipient: address(0),
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      poolDeployer: address(0)
    });
    return bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, new address[](0), new uint256[](0), uint256(0))
    );
  }

  function _swapAndIncreaseData(uint256 tokenId, uint256 amount0, uint256 amount1)
    internal
    view
    returns (bytes memory)
  {
    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: PROTOCOL,
      nfpm: AERO_NFPM,
      tokenId: tokenId,
      amount0: amount0,
      amount1: amount1,
      amount2: 0,
      recipient: address(0),
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      protocolFeeX64: 0,
      gasFeeX64: 0
    });
    return bytes.concat(
      abi.encode(SharedAerodromeStrategy.OperationType.SWAP_AND_INCREASE),
      abi.encode(params, new address[](0), new uint256[](0), uint256(0))
    );
  }

  function _swap(address trader, address tokenIn, address tokenOut, uint256 amountIn) internal {
    vm.startPrank(trader);
    IERC20(tokenIn).approve(AERO_SWAP_ROUTER, amountIn);
    IAeroSwapRouter(AERO_SWAP_ROUTER).exactInputSingle(
      IAeroSwapRouter.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        tickSpacing: TICK_SPACING,
        recipient: trader,
        deadline: block.timestamp,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );
    vm.stopPrank();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------------------------------------------

  function test_aero_swapAndMint_createsTrackedPosition() public {
    uint256 tokenId = _mint();

    assertEq(vault.getPositionCount(), 1);
    assertGt(_liquidity(tokenId), 0);
  }

  function test_aero_swapAndIncrease_addsLiquidity() public {
    uint256 tokenId = _mint();
    uint128 liquidityBefore = _liquidity(tokenId);

    _execute(_swapAndIncreaseData(tokenId, 0.2 ether, 600e6));

    assertGt(_liquidity(tokenId), liquidityBefore);
    assertEq(vault.getPositionCount(), 1);
  }

  function test_aero_withdraw_exitsPositionFully() public {
    _mint();
    uint256 wethBefore = IERC20(WETH).balanceOf(vaultOwner);
    uint256 usdcBefore = IERC20(USDC).balanceOf(vaultOwner);

    uint256[4] memory minAmounts;
    vm.startPrank(vaultOwner);
    vault.withdraw(vault.balanceOf(vaultOwner), minAmounts, false);
    vm.stopPrank();

    assertEq(vault.getPositionCount(), 0, "position untracked after full withdrawal");
    assertEq(vault.totalSupply(), 0);
    assertGt(IERC20(WETH).balanceOf(vaultOwner), wethBefore);
    assertGt(IERC20(USDC).balanceOf(vaultOwner), usdcBefore);
  }

  /// Deposit then immediately withdraw all minted shares against the real Aero NFPM: never more out than in, and
  /// no more than dust lost (mirrors the Aerodrome round-trip test).
  function test_aero_depositWithdraw_roundTrip_neverProfits() public {
    _mint();

    address depositor = makeAddr("aeroRoundTripDepositor");
    setErc20Balance(WETH, depositor, 100 ether);
    setErc20Balance(USDC, depositor, 200_000e6);

    uint256[4] memory totalBals = vault.getTotalBalances();
    uint256 wethIn = 0.5 ether;
    uint256 usdcIn = (wethIn * totalBals[1]) / totalBals[0] + 1;

    vm.startPrank(depositor);
    IERC20(WETH).approve(address(vault), type(uint256).max);
    IERC20(USDC).approve(address(vault), type(uint256).max);
    uint256 t0Before = IERC20(WETH).balanceOf(depositor);
    uint256 t1Before = IERC20(USDC).balanceOf(depositor);

    uint256 shares = vault.deposit([wethIn, usdcIn, uint256(0), 0], 50, 0);
    uint256 t0In = t0Before - IERC20(WETH).balanceOf(depositor);
    uint256 t1In = t1Before - IERC20(USDC).balanceOf(depositor);

    uint256[4] memory mins;
    uint256[4] memory got = vault.withdraw(shares, mins, false);
    vm.stopPrank();

    assertLe(got[0], t0In, "WETH out <= in");
    assertLe(got[1], t1In, "USDC out <= in");
    assertGe(got[0] + t0In / 200 + 5, t0In, "WETH loss is only dust");
    assertGe(got[1] + t1In / 200 + 5, t1In, "USDC loss is only dust");
  }

  function test_aero_previewWithdraw_includesLpValue() public {
    _mint();

    uint256[4] memory preview = vault.previewWithdraw(vault.balanceOf(vaultOwner));

    assertGt(preview[0], 0);
    assertGt(preview[1], 0);
  }

  /// The strategy values positions off-chain from the pool's fee-growth state. After real swaps on the Aero pool,
  /// that valuation must equal what burning and collecting the position actually pays.
  function test_aero_valuation_matchesRealizedExitAfterFees() public {
    uint256 tokenId = _mint();

    address trader = makeAddr("trader");
    setErc20Balance(WETH, trader, 10 ether);
    setErc20Balance(USDC, trader, 30_000e6);
    _swap(trader, WETH, USDC, 0.05 ether);
    _swap(trader, USDC, WETH, 150e6);

    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      aeroStrategy.getPositionAmountsSplit(AERO_NFPM, tokenId);
    assertGt(total0 - principal0, 0, "WETH fees accrued");
    assertGt(total1 - principal1, 0, "USDC fees accrued");

    uint128 liquidity = _liquidity(tokenId);
    vm.startPrank(address(vault));
    (uint256 burned0, uint256 burned1) = INFPM(AERO_NFPM).decreaseLiquidity(
      INFPM.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    (uint256 collected0, uint256 collected1) = INFPM(AERO_NFPM).collect(
      INFPM.CollectParams({
        tokenId: tokenId,
        recipient: address(vault),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    vm.stopPrank();

    assertApproxEqAbs(principal0, burned0, 1, "WETH principal");
    assertApproxEqAbs(principal1, burned1, 1, "USDC principal");
    assertApproxEqAbs(total0, collected0, 1, "WETH principal + fees");
    assertApproxEqAbs(total1, collected1, 1, "USDC principal + fees");
  }
}
