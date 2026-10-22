// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { ISharedV4Utils as IV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";

import { SharedVaultV4IntegrationTest } from "./Integration.SharedVault.V4.t.sol";

/// @notice Regression suite for GHSA-mqv2-4v6r-rmw6 against the REAL Base Uniswap-V4 PositionManager
///         (fork block 36_953_600). Each test asserts the FIX holds — the mirror of the (now removed)
///         exploit PoCs that proved the vulnerability. Fees are generated via a real pool donation.
contract GHSA_mqv2_V4Regression is SharedVaultV4IntegrationTest {
  uint16 internal constant PLATFORM_BPS = 1000;
  uint16 internal constant OWNER_BPS = 1000; // f = 20%

  SharedVault internal fv; // platform 10% + owner 10%
  uint256 internal fvId;

  function _setUpFeeVault() internal {
    configManager.setPlatformFeeBasisPoint(PLATFORM_BPS);
    fv = new SharedVault();
    token0.mint(address(fv), 10 ether);
    token1.mint(address(fv), 10 ether);
    address[4] memory toks = [address(token0), address(token1), address(0), address(0)];
    uint256[4] memory init = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    fv.initialize(
      "GHSA-V4-FeeVault", toks, init, vaultOwner, address(this), address(configManager), address(token0), OWNER_BPS
    );
    fvId = _mintPositionToOperator(poolKey, 0);
    IERC721(BASE_V4_POSM).approve(address(fv), fvId);
    fv.recoverPosition(BASE_V4_POSM, fvId, address(strategy), address(token0), address(token1));
  }

  function _uncollected(uint256 id) internal view returns (uint256 g0, uint256 g1) {
    (uint256 t0, uint256 t1, uint256 p0, uint256 p1) = strategy.getPositionAmountsSplit(BASE_V4_POSM, id);
    g0 = t0 - p0;
    g1 = t1 - p1;
  }

  function _execOn(SharedVault v, address caller, bytes memory stratData) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);
    vm.prank(caller);
    v.execute(actions);
  }

  function _swapAndIncreaseData(uint256 id, uint256 a0, uint256 a1) internal view returns (bytes memory) {
    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: a0 });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: a1 });
    IV4Utils.SwapAndIncreaseParams memory p = IV4Utils.SwapAndIncreaseParams({
      posm: BASE_V4_POSM,
      tokenId: id,
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    return bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_V4_POSM, id, abi.encodeCall(IV4Utils.swapAndIncrease, (p)), uint256(0), new address[](0), new uint256[](0)
      )
    );
  }

  function _decreaseAllData(uint256 id) internal view returns (bytes memory) {
    IV4Utils.DecreaseAndSwapParams memory d = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: posm.getPositionLiquidity(id),
        deadline: block.timestamp + 300,
        amount0Min: 0,
        amount1Min: 0,
        hookData: ""
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      swapDestToken: Currency.wrap(address(0)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory ins =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(d) });
    return bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_V4_POSM,
        id,
        abi.encodeCall(IV4Utils.execute, (BASE_V4_POSM, id, ins)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
  }

  function _plantOnVault(address planter, uint128 liquidity) internal returns (uint256 planted) {
    token0.mint(planter, 1 ether);
    token1.mint(planter, 1 ether);
    vm.startPrank(planter);
    token0.approve(address(permit2), type(uint256).max);
    token1.approve(address(permit2), type(uint256).max);
    permit2.approve(address(token0), BASE_V4_POSM, type(uint160).max, type(uint48).max);
    permit2.approve(address(token1), BASE_V4_POSM, type(uint160).max, type(uint48).max);
    bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // MINT_POSITION, SETTLE_PAIR
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(
      poolKey, TICK_LOWER, TICK_UPPER, uint256(liquidity), MAX_TOKEN_IN, MAX_TOKEN_IN, address(vault), bytes("")
    );
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
    planted = posm.nextTokenId();
    posm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
    vm.stopPrank();
  }

  // ───────── 1A: a deposit+withdraw round trip can no longer skim the performance fee
  // ─────────

  function test_GHSA_1A_fixed_depositCollectsFeesFirst_noProfit_recipientsPaid() public {
    _setUpFeeVault();
    _donateV4Fees(1 ether, 1 ether);
    (uint256 g0, uint256 g1) = _uncollected(fvId);
    assertGt(g0, 0.4 ether, "precondition: real fees accrued (token0)");

    uint256 ownerShares = fv.balanceOf(vaultOwner);
    uint256[4] memory holderClaimBefore = fv.previewWithdraw(ownerShares);
    uint256 ownerBal0 = token0.balanceOf(vaultOwner);
    uint256 ownerBal1 = token1.balanceOf(vaultOwner);

    address attacker = makeAddr("attacker");
    token0.mint(attacker, 1 ether);
    token1.mint(attacker, 1 ether);
    vm.startPrank(attacker);
    token0.approve(address(fv), type(uint256).max);
    token1.approve(address(fv), type(uint256).max);
    uint256 in0 = token0.balanceOf(attacker);
    uint256 in1 = token1.balanceOf(attacker);
    uint256 shares = fv.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 0, 0);
    in0 -= token0.balanceOf(attacker);
    in1 -= token1.balanceOf(attacker);

    // The deposit collected + charged fees FIRST, so there is nothing left uncollected to skim.
    (uint256 r0, uint256 r1) = _uncollected(fvId);
    assertEq(r0 + r1, 0, "deposit charged the accrued fees before increasing");
    assertApproxEqRel(token0.balanceOf(feeRecipient), g0 * PLATFORM_BPS / 10_000, 0.02e18, "platform fee paid (t0)");
    assertApproxEqRel(token1.balanceOf(feeRecipient), g1 * PLATFORM_BPS / 10_000, 0.02e18, "platform fee paid (t1)");
    assertApproxEqRel(token0.balanceOf(vaultOwner) - ownerBal0, g0 * OWNER_BPS / 10_000, 0.02e18, "owner fee paid (t0)");
    assertApproxEqRel(token1.balanceOf(vaultOwner) - ownerBal1, g1 * OWNER_BPS / 10_000, 0.02e18, "owner fee paid (t1)");

    uint256[4] memory mins;
    uint256[4] memory got = fv.withdraw(shares, mins, false);
    vm.stopPrank();

    // No risk-free profit: an instant round trip returns no more than was put in.
    assertLe(got[0], in0, "round-trip token0 out <= in");
    assertLe(got[1], in1, "round-trip token1 out <= in");

    // Existing holder is not diluted — their claim is preserved (fees belonged to the recipients).
    uint256[4] memory holderClaimAfter = fv.previewWithdraw(ownerShares);
    assertApproxEqRel(holderClaimAfter[0], holderClaimBefore[0], 0.001e18, "holder claim preserved (t0)");
    assertApproxEqRel(holderClaimAfter[1], holderClaimBefore[1], 0.001e18, "holder claim preserved (t1)");
  }

  // ───────── 1B: deposits with slippageBps > 0 no longer revert once fees have accrued
  // ─────────

  function test_GHSA_1B_fixed_slippageDepositSucceeds_largeFees() public {
    _donateV4Fees(1 ether, 1 ether);
    token0.mint(depositor, 2 ether);
    token1.mint(depositor, 2 ether);
    vm.startPrank(depositor);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 50, 0);
    vm.stopPrank();
    assertGt(shares, 0, "slippage-guarded deposit succeeds after fees accrue");
  }

  function test_GHSA_1B_fixed_slippageDepositSucceeds_smallFees() public {
    _donateV4Fees(0.001 ether, 0.001 ether);
    token0.mint(depositor, 2 ether);
    token1.mint(depositor, 2 ether);
    vm.startPrank(depositor);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 50, 0);
    vm.stopPrank();
    assertGt(shares, 0, "slippage-guarded deposit succeeds after small fees accrue");
  }

  // ───────── 1C: swapAndIncrease charges the performance fee before increasing
  // ─────────

  function test_GHSA_1C_fixed_swapAndIncreaseChargesFees() public {
    _setUpFeeVault();
    _donateV4Fees(1 ether, 1 ether);
    (uint256 g0,) = _uncollected(fvId);
    uint256 ownerBal0 = token0.balanceOf(vaultOwner);

    _execOn(fv, vaultOwner, _swapAndIncreaseData(fvId, 0.1 ether, 0.1 ether));

    (uint256 r0, uint256 r1) = _uncollected(fvId);
    assertEq(r0 + r1, 0, "fees collected by swapAndIncrease");
    assertApproxEqRel(token0.balanceOf(feeRecipient), g0 * PLATFORM_BPS / 10_000, 0.02e18, "platform fee paid");
    assertApproxEqRel(token0.balanceOf(vaultOwner) - ownerBal0, g0 * OWNER_BPS / 10_000, 0.02e18, "owner fee paid");
  }

  // ───────── Claim 2: swapAndIncrease tracks the position; planted NFTs can't hide value
  // ─────────

  function test_GHSA_2_fixed_swapAndIncreaseTracksPlantedNft_noNavCollapse() public {
    uint256 planted = _plantOnVault(makeAddr("planter"), 1e6);
    assertEq(IERC721(BASE_V4_POSM).ownerOf(planted), address(vault), "vault owns the planted NFT");
    assertEq(vault.getPositionCount(), 1, "planted NFT starts untracked");

    address admin = makeAddr("admin");
    vm.prank(vaultOwner);
    vault.grantAdminRole(admin);

    uint256[4] memory totBefore = vault.getTotalBalances();

    _execOn(vault, admin, _swapAndIncreaseData(planted, 9 ether, 9 ether));

    // The previously-untracked NFT is now tracked, so the funds moved into it stay in NAV.
    assertEq(vault.getPositionCount(), 2, "planted NFT is now tracked after swapAndIncrease");
    uint256[4] memory totAfter = vault.getTotalBalances();
    assertApproxEqRel(totAfter[0], totBefore[0], 0.01e18, "NAV preserved (token0) - no collapse");
    assertApproxEqRel(totAfter[1], totBefore[1], 0.01e18, "NAV preserved (token1) - no collapse");
  }

  function test_GHSA_2_fixed_fullSandwichYieldsNoProfit() public {
    uint256 planted = _plantOnVault(makeAddr("planter"), 1e6);
    address admin = makeAddr("admin");
    vm.prank(vaultOwner);
    vault.grantAdminRole(admin);

    _execOn(vault, admin, _swapAndIncreaseData(planted, 9 ether, 9 ether)); // now tracked, NAV intact

    address colluder = makeAddr("colluder");
    token0.mint(colluder, 1 ether);
    token1.mint(colluder, 1 ether);
    vm.startPrank(colluder);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256 in0 = token0.balanceOf(colluder);
    uint256 in1 = token1.balanceOf(colluder);
    uint256 shares = vault.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 0, 0);
    in0 -= token0.balanceOf(colluder);
    in1 -= token1.balanceOf(colluder);
    vm.stopPrank();

    _execOn(vault, admin, _decreaseAllData(planted)); // pull it back to idle

    uint256[4] memory mins;
    vm.prank(colluder);
    uint256[4] memory got = vault.withdraw(shares, mins, false);

    assertLe(got[0], in0, "colluder cannot profit (token0)");
    assertLe(got[1], in1, "colluder cannot profit (token1)");
  }
}
