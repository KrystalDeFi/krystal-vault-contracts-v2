// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, PANCAKE_NFPM as NFPM } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { SharedStrategyBeacon } from "../../contracts/shared-vault/strategies/SharedStrategyBeacon.sol";
import { SharedStrategyProxy } from "../../contracts/shared-vault/strategies/SharedStrategyProxy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";

import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

interface INFPMPositions {
  function positions(
    uint256 tokenId
  )
    external
    view
    returns (
      uint96,
      address,
      address,
      address,
      uint24,
      int24,
      int24,
      uint128 liquidity,
      uint256,
      uint256,
      uint128,
      uint128
    );
}

/// @notice Integration tests for PancakeSwap V3 LP operations via SharedV3Strategy.
///         PancakeSwap V3 is ABI-compatible with Uniswap V3: same positions() layout (uint24 fee),
///         same IUniswapV3Factory.getPool(address,address,uint24) selector, same increaseLiquidity struct.
///         The only PancakeSwap quirk (non-canonical slot0 encoding) is already handled in SharedV3Strategy
///         via staticcall + assembly, so no dedicated strategy is needed.
contract SharedVaultPancakeV3IntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

  // PancakeSwap V3 WETH/USDC 0.01% pool on Base — protocol=0 (Uniswap V3-compatible ABI)
  uint24 constant FEE_TIER = 100;
  int24 constant TICK_LOWER = -887_000;
  int24 constant TICK_UPPER = 887_000;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  SharedV3Strategy public v3Strategy;
  SharedStrategyBeacon public beacon;
  SharedStrategyProxy public proxy;
  SharedVault public vault;

  address public vaultOwner = USER;
  address public feeRecipient;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 36_953_600);
    vm.selectFork(fork);

    feeRecipient = makeAddr("feeRecipient");

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    address[] memory nfpms = new address[](1);
    nfpms[0] = NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(vaultOwner, new address[](0), new address[](0), feeRecipient, 0, nfpms, new address[](0));

    lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));
    beacon = new SharedStrategyBeacon(address(v3Strategy), vaultOwner);
    proxy = new SharedStrategyProxy(address(beacon));

    // Whitelist the proxy — proxy address is stable across upgrades
    address[] memory targets = new address[](1);
    targets[0] = address(proxy);
    configManager.setWhitelistTargets(targets, true);

    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    IERC20(USDC).approve(address(vaultFactory), 3000e6);

    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(1 ether), 3000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-PancakeV3", vaultTokens, initialAmounts)));

    vm.stopPrank();
  }

  // =========================================================
  // SWAP_AND_MINT: create a PancakeSwap V3 LP position
  // =========================================================

  function test_pancake_swapAndMint_createsPosition() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndMintData(0.5 ether, 1500e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    assertEq(vault.getPositionCount(), 1, "should have 1 tracked Pancake LP position");
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);
    assertGt(tokenId, 0, "tokenId must be non-zero");
    console.log("Pancake SWAP_AND_MINT: tokenId =", tokenId);

    vm.stopPrank();
  }

  // =========================================================
  // SWAP_AND_INCREASE: add liquidity to existing position
  // =========================================================

  function test_pancake_swapAndIncrease_addsLiquidity() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
    mintActions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndMintData(0.5 ether, 1500e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(mintActions);
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);

    (, , , , , , , uint128 liquidityBefore, , , , ) = INFPMPositions(NFPM).positions(tokenId);

    ISharedVault.Action[] memory increaseActions = new ISharedVault.Action[](1);
    increaseActions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndIncreaseData(tokenId, 0.2 ether, 600e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(increaseActions);

    (, , , , , , , uint128 liquidityAfter, , , , ) = INFPMPositions(NFPM).positions(tokenId);
    assertGt(liquidityAfter, liquidityBefore, "liquidity must increase after SWAP_AND_INCREASE");
    assertEq(vault.getPositionCount(), 1, "position count unchanged after increase");
    console.log("Pancake SWAP_AND_INCREASE: liquidity", liquidityBefore, "->", liquidityAfter);

    vm.stopPrank();
  }

  // =========================================================
  // vault.withdraw() — exitProportional removes proportional liquidity
  // =========================================================

  function test_pancake_withdraw_exitsProportionally() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
    mintActions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndMintData(0.5 ether, 1500e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(mintActions);

    uint256 wethBefore = IERC20(WETH).balanceOf(vaultOwner);
    uint256 usdcBefore = IERC20(USDC).balanceOf(vaultOwner);

    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = vault.withdraw(shares, minAmounts, false);

    assertEq(vault.getPositionCount(), 0, "LP position removed after full withdrawal");
    assertEq(vault.totalSupply(), 0, "no shares remaining");
    assertGt(IERC20(WETH).balanceOf(vaultOwner) - wethBefore + withdrawn[0], 0, "WETH returned");
    assertGt(IERC20(USDC).balanceOf(vaultOwner) - usdcBefore + withdrawn[1], 0, "USDC returned");
    console.log("Pancake withdraw: WETH =", withdrawn[0], "USDC =", withdrawn[1]);

    vm.stopPrank();
  }

  // =========================================================
  // Second depositor proportional shares with active Pancake LP
  // =========================================================

  function test_pancake_secondDepositor_proportional() public {
    vm.startPrank(vaultOwner);
    ISharedVault.Action[] memory mintActions = new ISharedVault.Action[](1);
    mintActions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndMintData(0.5 ether, 1500e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(mintActions);
    vm.stopPrank();

    address player = makeAddr("player2");
    setErc20Balance(WETH, player, 10 ether);
    setErc20Balance(USDC, player, 30_000e6);

    uint256 totalSupplyBefore = vault.totalSupply();
    uint256[4] memory totalBals = vault.getTotalBalances();

    uint256 wethIn = 0.5 ether;
    uint256 usdcIn = totalBals[0] > 0 ? (wethIn * totalBals[1]) / totalBals[0] + 1 : 1500e6;

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethIn);
    IERC20(USDC).approve(address(vault), usdcIn);

    uint256 shares = vault.deposit([wethIn, usdcIn, uint256(0), 0], 0);
    vm.stopPrank();

    assertGt(shares, 0, "second depositor should receive shares");
    assertGt(vault.totalSupply(), totalSupplyBefore, "total supply must increase");
    console.log("Pancake second depositor shares =", shares);
  }

  // =========================================================
  // previewWithdraw reflects Pancake LP value
  // =========================================================

  function test_pancake_previewWithdraw_includesLpValue() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(proxy),
      _swapAndMintData(0.5 ether, 1500e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory preview = vault.previewWithdraw(shares);

    assertGt(preview[0], 0, "WETH preview should reflect Pancake LP value");
    assertGt(preview[1], 0, "USDC preview should reflect Pancake LP value");
    console.log("Pancake previewWithdraw: WETH =", preview[0], "USDC =", preview[1]);

    vm.stopPrank();
  }

  // =========================================================
  // Beacon upgrade — proxy address unchanged, new impl takes effect
  // =========================================================

  function test_pancake_beaconUpgrade_newImplUsedWithoutRewhitelisting() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(proxy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1, "position created via v1 impl");

    // Upgrade: deploy new impl and update beacon
    SharedV3Strategy newImpl = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));
    beacon.setImplementation(address(newImpl));
    assertEq(beacon.implementation(), address(newImpl), "beacon updated to new impl");

    // Proxy address and whitelist unchanged — same action.target works
    uint256 tokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);
    ISharedVault.Action[] memory increaseActions = new ISharedVault.Action[](1);
    increaseActions[0] = ISharedVault.Action(address(proxy), _swapAndIncreaseData(tokenId, 0.1 ether, 300e6), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(increaseActions);

    assertEq(vault.getPositionCount(), 1, "position still tracked after upgrade");
    console.log("Pancake beacon upgrade: new impl =", address(newImpl));

    vm.stopPrank();
  }

  // =========================================================
  // Helpers
  // =========================================================

  function _swapAndMintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0, // PancakeSwap V3 is Uniswap V3-compatible
      nfpm: NFPM,
      token0: WETH,
      token1: USDC,
      fee: FEE_TIER,
      tickSpacing: 1,
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

    return
      bytes.concat(
        abi.encode(SharedV3Strategy.OperationType.SWAP_AND_MINT),
        abi.encode(params, approveTokens, approveAmounts, uint256(0))
      );
  }

  function _swapAndIncreaseData(
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1
  ) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: NFPM,
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

    return
      bytes.concat(
        abi.encode(SharedV3Strategy.OperationType.SWAP_AND_INCREASE),
        abi.encode(params, approveTokens, approveAmounts, uint256(0))
      );
  }
}
