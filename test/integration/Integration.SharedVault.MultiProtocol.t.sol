// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, USDC, NFPM, PANCAKE_NFPM } from "../TestCommon.t.sol";

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

/// @notice Integration tests for a SharedVault with multiple protocol strategies active simultaneously.
///         Validates that UniswapV3 and PancakeSwap V3 positions coexist correctly via SharedV3Strategy.
///         Both protocols share the same strategy implementation; separate beacon+proxy pairs give
///         independent whitelist control (revoking one doesn't affect the other).
contract SharedVaultMultiProtocolIntegrationTest is TestCommon {
  address constant V3_UTILS = 0xFb61514860896FCC667E8565eACC1993Fafd97Af;

  // Uniswap V3 WETH/USDC 0.05% pool on Base
  uint24 constant UNI_FEE = 500;
  int24 constant UNI_TICK_SPACING = 10;

  // PancakeSwap V3 WETH/USDC 0.01% pool on Base
  uint24 constant CAKE_FEE = 100;
  int24 constant CAKE_TICK_SPACING = 1;

  int24 constant TICK_LOWER = -887_200;
  int24 constant TICK_UPPER = 887_200;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedVault public vaultImplementation;
  LpFeeTaker public lpFeeTaker;
  // Both protocols use SharedV3Strategy; separate beacons/proxies allow independent revocation & upgrades
  SharedV3Strategy public v3Strategy;
  SharedStrategyBeacon public v3Beacon;
  SharedStrategyProxy public v3Proxy;
  SharedStrategyBeacon public pancakeBeacon;
  SharedStrategyProxy public pancakeProxy;
  SharedVault public vault;

  address public vaultOwner = USER;
  address public feeRecipient;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 45_893_511);
    vm.selectFork(fork);

    feeRecipient = makeAddr("feeRecipient");

    setErc20Balance(WETH, vaultOwner, 100 ether);
    setErc20Balance(USDC, vaultOwner, 200_000e6);
    vm.deal(vaultOwner, 100 ether);

    vm.startPrank(vaultOwner);

    // Both NFPMs whitelisted — SharedV3Strategy enforces per-call via configManager
    address[] memory nfpms = new address[](2);
    nfpms[0] = NFPM;
    nfpms[1] = PANCAKE_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(vaultOwner, new address[](0), new address[](0), feeRecipient, 0, nfpms, new address[](0));

    lpFeeTaker = new LpFeeTaker();
    // Single implementation shared by both protocol proxies
    v3Strategy = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));

    v3Beacon = new SharedStrategyBeacon(address(v3Strategy), vaultOwner);
    v3Proxy = new SharedStrategyProxy(address(v3Beacon));

    pancakeBeacon = new SharedStrategyBeacon(address(v3Strategy), vaultOwner);
    pancakeProxy = new SharedStrategyProxy(address(pancakeBeacon));

    // Whitelist both proxy addresses independently
    address[] memory targets = new address[](2);
    targets[0] = address(v3Proxy);
    targets[1] = address(pancakeProxy);
    configManager.setWhitelistTargets(targets, true);

    vaultImplementation = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(vaultOwner, address(configManager), address(vaultImplementation), WETH);

    IERC20(WETH).approve(address(vaultFactory), 2 ether);
    IERC20(USDC).approve(address(vaultFactory), 6000e6);

    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(2 ether), 6000e6, 0, 0];
    vault = SharedVault(payable(vaultFactory.createVault("SharedVault-MultiProtocol", vaultTokens, initialAmounts, 0)));

    vm.stopPrank();
  }

  // =========================================================
  // Both strategies create LP positions simultaneously
  // =========================================================

  function test_multiProtocol_bothStrategies_createPositions() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    assertEq(vault.getPositionCount(), 2, "should have 2 tracked LP positions (one per protocol)");

    uint256 uniTokenId = IERC721Enumerable(NFPM).tokenOfOwnerByIndex(address(vault), 0);
    uint256 cakeTokenId = IERC721Enumerable(PANCAKE_NFPM).tokenOfOwnerByIndex(address(vault), 0);

    assertGt(uniTokenId, 0, "UniswapV3 tokenId must be non-zero");
    assertGt(cakeTokenId, 0, "PancakeV3 tokenId must be non-zero");
    console.log("Multi-protocol: UniV3 tokenId =", uniTokenId, "PancakeV3 tokenId =", cakeTokenId);

    vm.stopPrank();
  }

  // =========================================================
  // Total balances includes LP value from both protocols
  // =========================================================

  function test_multiProtocol_totalBalances_includesBothLpValues() public {
    vm.startPrank(vaultOwner);

    uint256[4] memory idleBefore = vault.getIdleBalances();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    uint256[4] memory idleAfter = vault.getIdleBalances();
    uint256[4] memory totalAfter = vault.getTotalBalances();

    assertLt(idleAfter[0], idleBefore[0], "WETH idle must drop after LP deployment");
    assertLt(idleAfter[1], idleBefore[1], "USDC idle must drop after LP deployment");
    assertGt(totalAfter[0], idleAfter[0], "total WETH must exceed idle (LP positions add value)");
    assertGt(totalAfter[1], idleAfter[1], "total USDC must exceed idle (LP positions add value)");
    console.log("Multi-protocol total WETH =", totalAfter[0], "USDC =", totalAfter[1]);

    vm.stopPrank();
  }

  // =========================================================
  // Second depositor receives shares priced on combined LP value
  // =========================================================

  function test_multiProtocol_secondDepositor_proportional() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();

    address player = makeAddr("player4");
    setErc20Balance(WETH, player, 10 ether);
    setErc20Balance(USDC, player, 30_000e6);

    uint256 totalSupplyBefore = vault.totalSupply();
    uint256[4] memory totalBals = vault.getTotalBalances();

    uint256 wethIn = 0.5 ether;
    uint256 usdcIn = totalBals[0] > 0 ? (wethIn * totalBals[1]) / totalBals[0] + 1 : 3000e6;

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethIn);
    IERC20(USDC).approve(address(vault), usdcIn);

    uint256 shares = vault.deposit([wethIn, usdcIn, uint256(0), 0], 0);
    vm.stopPrank();

    assertGt(shares, 0, "second depositor must receive shares");
    assertGt(vault.totalSupply(), totalSupplyBefore, "total supply must increase");
    console.log("Multi-protocol second depositor shares =", shares);
  }

  // =========================================================
  // Full withdrawal: exitProportional fires for both strategies
  // =========================================================

  function test_multiProtocol_fullWithdraw_exitsAllPositions() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    assertEq(vault.getPositionCount(), 2, "two positions before withdraw");

    uint256 wethBefore = IERC20(WETH).balanceOf(vaultOwner);
    uint256 usdcBefore = IERC20(USDC).balanceOf(vaultOwner);

    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = vault.withdraw(shares, minAmounts, false);

    assertEq(vault.getPositionCount(), 0, "all LP positions removed after full withdrawal");
    assertEq(vault.totalSupply(), 0, "no shares remaining");
    assertGt(IERC20(WETH).balanceOf(vaultOwner) - wethBefore + withdrawn[0], 0, "WETH must be returned");
    assertGt(IERC20(USDC).balanceOf(vaultOwner) - usdcBefore + withdrawn[1], 0, "USDC must be returned");
    console.log("Multi-protocol full withdraw: WETH =", withdrawn[0], "USDC =", withdrawn[1]);

    vm.stopPrank();
  }

  // =========================================================
  // Partial withdrawal: proportional exit from both positions
  // =========================================================

  function test_multiProtocol_partialWithdraw_reducesLiquidity() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);
    vm.stopPrank();

    address player = makeAddr("player5");
    setErc20Balance(WETH, player, 10 ether);
    setErc20Balance(USDC, player, 30_000e6);

    uint256[4] memory totalBals = vault.getTotalBalances();
    uint256 wethIn = 0.5 ether;
    uint256 usdcIn = totalBals[0] > 0 ? (wethIn * totalBals[1]) / totalBals[0] + 1 : 3000e6;

    vm.startPrank(player);
    IERC20(WETH).approve(address(vault), wethIn);
    IERC20(USDC).approve(address(vault), usdcIn);
    vault.deposit([wethIn, usdcIn, uint256(0), 0], 0);
    vm.stopPrank();

    vm.startPrank(vaultOwner);
    uint256 ownerShares = vault.balanceOf(vaultOwner);
    uint256 halfShares = ownerShares / 2;
    uint256 posCountBefore = vault.getPositionCount();

    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = vault.withdraw(halfShares, minAmounts, false);

    assertEq(vault.getPositionCount(), posCountBefore, "positions should remain after partial withdraw");
    assertGt(withdrawn[0] + withdrawn[1], 0, "tokens must be returned for partial withdraw");
    console.log("Multi-protocol partial withdraw: WETH =", withdrawn[0], "USDC =", withdrawn[1]);

    vm.stopPrank();
  }

  // =========================================================
  // previewWithdraw reflects combined UniV3 + PancakeV3 LP value
  // =========================================================

  function test_multiProtocol_previewWithdraw_reflectsBothLpValues() public {
    vm.startPrank(vaultOwner);

    uint256[4] memory previewBefore = vault.previewWithdraw(vault.balanceOf(vaultOwner));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    vault.execute(actions);

    uint256[4] memory previewAfter = vault.previewWithdraw(vault.balanceOf(vaultOwner));

    assertGt(previewAfter[0], 0, "WETH preview must be non-zero with active LP");
    assertGt(previewAfter[1], 0, "USDC preview must be non-zero with active LP");
    console.log("Multi-protocol preview WETH before LP:", previewBefore[0], "after LP:", previewAfter[0]);
    console.log("Multi-protocol preview USDC before LP:", previewBefore[1], "after LP:", previewAfter[1]);

    vm.stopPrank();
  }

  // =========================================================
  // createVault with both strategies atomically
  // =========================================================

  function test_multiProtocol_createVault_withBothStrategies() public {
    vm.startPrank(vaultOwner);

    uint256 wethAmt = 2 ether;
    uint256 usdcAmt = 6000e6;

    IERC20(USDC).approve(address(vaultFactory), usdcAmt);

    address[4] memory vaultTokens = [WETH, USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [wethAmt, usdcAmt, uint256(0), 0];

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(
      address(v3Proxy),
      _uniV3MintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );
    actions[1] = ISharedVault.Action(
      address(pancakeProxy),
      _pancakeMintData(0.4 ether, 1200e6),
      ISharedCommon.CallType.DELEGATECALL
    );

    SharedVault vault2 = SharedVault(
      payable(
        vaultFactory.createVault{ value: wethAmt }("MultiProtocol-AtomicCreate", vaultTokens, initialAmounts, 0, actions)
      )
    );

    assertEq(vault2.getPositionCount(), 2, "vault created with 2 LP positions atomically");
    console.log("createVault with 2 strategies: position count =", vault2.getPositionCount());

    vm.stopPrank();
  }

  // =========================================================
  // Beacon upgrade — each proxy independently upgradeable
  // =========================================================

  function test_multiProtocol_beaconUpgrade_independentPerStrategy() public {
    vm.startPrank(vaultOwner);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(address(v3Proxy), _uniV3MintData(0.4 ether, 1200e6), ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(pancakeProxy), _pancakeMintData(0.4 ether, 1200e6), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 2, "two positions before upgrade");

    // Upgrade only the V3 beacon — pancakeProxy's beacon is unaffected
    SharedV3Strategy newV3Impl = new SharedV3Strategy(V3_UTILS, address(lpFeeTaker));
    v3Beacon.setImplementation(address(newV3Impl));
    assertEq(v3Beacon.implementation(), address(newV3Impl), "v3 beacon updated");

    // Both proxies still work — ConfigManager whitelist unchanged
    ISharedVault.Action[] memory actions2 = new ISharedVault.Action[](2);
    actions2[0] = ISharedVault.Action(address(v3Proxy), _uniV3MintData(0.2 ether, 600e6), ISharedCommon.CallType.DELEGATECALL);
    actions2[1] = ISharedVault.Action(address(pancakeProxy), _pancakeMintData(0.2 ether, 600e6), ISharedCommon.CallType.DELEGATECALL);
    vault.execute(actions2);

    assertEq(vault.getPositionCount(), 4, "two more positions after upgrade");
    console.log("Multi-protocol beacon upgrade: v3 new impl =", address(newV3Impl));

    vm.stopPrank();
  }

  // =========================================================
  // Helpers
  // =========================================================

  function _uniV3MintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: NFPM,
      token0: WETH,
      token1: USDC,
      fee: UNI_FEE,
      tickSpacing: UNI_TICK_SPACING,
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

  function _pancakeMintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = WETH;
    approveTokens[1] = USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0, // PancakeSwap V3 is Uniswap V3-compatible
      nfpm: PANCAKE_NFPM,
      token0: WETH,
      token1: USDC,
      fee: CAKE_FEE,
      tickSpacing: CAKE_TICK_SPACING,
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
}
