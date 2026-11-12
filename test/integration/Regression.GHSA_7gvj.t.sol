// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import { WETH, USDC } from "../TestCommon.t.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IWETH9 } from "../../contracts/public-vault/interfaces/IWETH9.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { ISharedV4Utils as IV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { SharedVaultIntegrationTest } from "./Integration.SharedVault.t.sol";
import { SharedVaultV4IntegrationTest } from "./Integration.SharedVault.V4.t.sol";

/// @notice Regression suite for GHSA-7gvj-vm6c-xxqf against the REAL Base Uniswap V3 NFPM (fork block 36_953_600).
///         Before the fix, `deposit{value: x}` reverted with `StrategyCallFailed` whenever the vault held a
///         position, because DELEGATECALL keeps `msg.value` and `depositProportional` was not payable.
contract GHSA_7gvj_V3Regression is SharedVaultIntegrationTest {
  function test_GHSA_7gvj_nativeEthDeposit_withLiveV3Position_matchesWethDeposit_andRefundsExcess() public {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(v3Strategy), _swapAndMintData(0.5 ether, 1500e6), ISharedCommon.CallType.DELEGATECALL
    );
    vm.prank(vaultOwner);
    vault.execute(actions);
    assertEq(vault.getPositionCount(), 1, "vault holds a live position");

    address player = makeAddr("player");
    setErc20Balance(WETH, player, 10 ether);
    setErc20Balance(USDC, player, 30_000e6);
    vm.deal(player, 10 ether);
    uint256[4] memory totalBals = vault.getTotalBalances();
    uint256 usdcIn = (0.5 ether * totalBals[1]) / totalBals[0] + 1; // USDC binds at ~0.5 ETH of value
    uint256[4] memory amts = [uint256(1 ether), usdcIn, 0, 0]; // 1 ETH offered, so ~0.5 ETH is excess
    vm.prank(player);
    IERC20(USDC).approve(address(vault), usdcIn);
    uint256 snap = vm.snapshotState();

    uint256 ethBefore = player.balance;
    vm.prank(player);
    uint256 sharesEth = vault.deposit{ value: 1 ether }(amts, 0, 0);
    uint256 ethSpent = ethBefore - player.balance;
    assertGt(sharesEth, 0, "native ETH deposit succeeds with a live position");
    assertGt(ethSpent, 0, "ETH was used");
    assertLt(ethSpent, 1 ether, "excess ETH refunded");
    assertEq(address(vault).balance, 0, "no raw ETH left in the vault");

    vm.revertToState(snap);
    vm.prank(player);
    IERC20(WETH).approve(address(vault), 1 ether);
    uint256 wethBefore = IERC20(WETH).balanceOf(player);
    vm.prank(player);
    uint256 sharesWeth = vault.deposit(amts, 0, 0);
    assertEq(sharesEth, sharesWeth, "ETH and WETH deposits mint the same shares");
    assertEq(ethSpent, wethBefore - IERC20(WETH).balanceOf(player), "ETH spent equals WETH pulled");
  }
}

/// @notice The V4 half of GHSA-7gvj: a native-ETH deposit into a vault holding a NATIVE-currency V4 position, on
///         the REAL Base Uniswap V4 PositionManager. The fix makes the strategy's native unwrap/wrap path run with
///         excess deposit ETH sitting in the vault for the first time; it must neither consume nor wrap that excess.
contract GHSA_7gvj_V4Regression is SharedVaultV4IntegrationTest {
  function test_GHSA_7gvj_nativeEthDeposit_intoNativeV4Position_refundsExcess_andMatchesWethDeposit() public {
    // Native (ETH / token0) pool vault with a position, as in test_withdrawFull_nativeCurrencyPool_*.
    PoolKey memory nativeKey = PoolKey({
      currency0: Currency.wrap(address(0)),
      currency1: Currency.wrap(address(token0)),
      fee: LP_FEE,
      tickSpacing: TICK_SPACING,
      hooks: IHooks(address(0))
    });
    posm.initializePool(nativeKey, SQRT_PRICE_1_1);

    SharedVault nativeVault = new SharedVault();
    vm.deal(address(this), 10 ether);
    IWETH9(BASE_WETH).deposit{ value: 10 ether }();
    IERC20(BASE_WETH).transfer(address(nativeVault), 10 ether);
    token0.mint(address(nativeVault), 10 ether);
    nativeVault.initialize(
      "SharedVault-V4-Native-7gvj",
      [BASE_WETH, address(token0), address(0), address(0)],
      [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)],
      vaultOwner,
      address(this),
      address(configManager),
      BASE_WETH,
      0
    );

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: nativeKey,
      mintParams: IV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(
      address(strategy),
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM, uint256(0), abi.encodeCall(IV4Utils.swapAndMint, (mintParams)), uint256(0),
          new address[](0), new uint256[](0)
        )
      ),
      ISharedCommon.CallType.DELEGATECALL
    );
    vm.prank(vaultOwner);
    nativeVault.execute(actions);
    (,, uint256 nativeTokenId,,) = nativeVault.getPosition(0);
    uint128 liqBefore = posm.getPositionLiquidity(nativeTokenId);

    // A fresh depositor. Its WETH9 balance/allowance slots are primed (to their true value, 0) so the cached
    // fork never needs a live read. WETH9 layout: balanceOf at slot 3, allowance at slot 4.
    address player = makeAddr("ghsa7gvjV4Player");
    vm.store(BASE_WETH, keccak256(abi.encode(player, uint256(3))), bytes32(0));
    vm.store(
      BASE_WETH, keccak256(abi.encode(address(nativeVault), keccak256(abi.encode(player, uint256(4))))), bytes32(0)
    );
    vm.deal(player, 10 ether);
    token0.mint(player, 10 ether);
    vm.prank(player);
    token0.approve(address(nativeVault), type(uint256).max);

    // 2 ETH offered against 1 token0; the vault ratio is ~1:1, so ~1 ETH is excess.
    uint256[4] memory amts = [uint256(2 ether), uint256(1 ether), 0, 0];
    uint256 snap = vm.snapshotState();

    uint256 ethBefore = player.balance;
    vm.prank(player);
    uint256 sharesEth = nativeVault.deposit{ value: 2 ether }(amts, 0, 0);
    uint256 ethSpent = ethBefore - player.balance;
    assertGt(posm.getPositionLiquidity(nativeTokenId), liqBefore, "native V4 position topped up");
    assertGt(ethSpent, 0, "ETH was used");
    assertLt(ethSpent, 2 ether, "excess ETH refunded");
    assertEq(address(nativeVault).balance, 0, "no raw ETH left in the vault");

    vm.revertToState(snap);
    vm.prank(player);
    IWETH9(BASE_WETH).deposit{ value: 2 ether }();
    vm.prank(player);
    IERC20(BASE_WETH).approve(address(nativeVault), 2 ether);
    uint256 wethBefore = IERC20(BASE_WETH).balanceOf(player);
    vm.prank(player);
    uint256 sharesWeth = nativeVault.deposit(amts, 0, 0);
    assertEq(sharesEth, sharesWeth, "ETH and WETH deposits mint the same shares");
    assertEq(ethSpent, wethBefore - IERC20(BASE_WETH).balanceOf(player), "ETH spent equals WETH pulled");
  }
}
