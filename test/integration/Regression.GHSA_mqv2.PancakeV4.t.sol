// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";
import {
  ISharedPancakeV4Utils as IPancakeV4Utils
} from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";

import { SharedVaultPancakeV4IntegrationTest } from "./Integration.SharedVault.PancakeV4.t.sol";

/// @notice Pancake-Infinity twin of GHSA_mqv2_V4Regression against the REAL Base CLPositionManager.
///         Asserts the FIX holds (1A/1B/1C fee-collection; the untracked-NFT (claim 2) path).
contract GHSA_mqv2_PancakeV4Regression is SharedVaultPancakeV4IntegrationTest {
  uint16 internal constant PLATFORM_BPS = 1000;
  uint16 internal constant OWNER_BPS = 1000;

  SharedVault internal fv;
  uint256 internal fvId;

  function _setUpFeeVault() internal {
    configManager.setPlatformFeeBasisPoint(PLATFORM_BPS);
    fv = new SharedVault();
    token0.mint(address(fv), 10 ether);
    token1.mint(address(fv), 10 ether);
    address[4] memory toks = [address(token0), address(token1), address(0), address(0)];
    uint256[4] memory init = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    fv.initialize(
      "GHSA-Pancake-FeeVault", toks, init, vaultOwner, address(this), address(configManager), address(token0), OWNER_BPS
    );
    fvId = _mintPositionToOperator(poolKey);
    IERC721(BASE_PANCAKE_V4_POSM).approve(address(fv), fvId);
    fv.recoverPosition(BASE_PANCAKE_V4_POSM, fvId, address(strategy), address(token0), address(token1));
  }

  function _uncollected(uint256 id) internal view returns (uint256 g0, uint256 g1) {
    (uint256 t0, uint256 t1, uint256 p0, uint256 p1) = strategy.getPositionAmountsSplit(BASE_PANCAKE_V4_POSM, id);
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
    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: a0 });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: a1 });
    IPancakeV4Utils.SwapAndIncreaseParams memory p = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: id,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    return bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_PANCAKE_V4_POSM,
        id,
        abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (p)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
  }

  function test_GHSA_1A_pancake_fixed_depositCollectsFeesFirst_noProfit_recipientsPaid() public {
    _setUpFeeVault();
    _donatePancakeV4Fees(1 ether, 1 ether);
    (uint256 g0,) = _uncollected(fvId);
    assertGt(g0, 0.4 ether, "precondition: real fees accrued");

    uint256 ownerShares = fv.balanceOf(vaultOwner);
    uint256[4] memory holderClaimBefore = fv.previewWithdraw(ownerShares);
    uint256 ownerBal0 = token0.balanceOf(vaultOwner);

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

    (uint256 r0, uint256 r1) = _uncollected(fvId);
    assertEq(r0 + r1, 0, "deposit charged the accrued fees before increasing");
    assertApproxEqRel(token0.balanceOf(feeRecipient), g0 * PLATFORM_BPS / 10_000, 0.02e18, "platform fee paid");
    assertApproxEqRel(token0.balanceOf(vaultOwner) - ownerBal0, g0 * OWNER_BPS / 10_000, 0.02e18, "owner fee paid");

    uint256[4] memory mins;
    uint256[4] memory got = fv.withdraw(shares, mins, false);
    vm.stopPrank();

    assertLe(got[0], in0, "round-trip token0 out <= in");
    assertLe(got[1], in1, "round-trip token1 out <= in");

    uint256[4] memory holderClaimAfter = fv.previewWithdraw(ownerShares);
    assertApproxEqRel(holderClaimAfter[0], holderClaimBefore[0], 0.001e18, "holder claim preserved (t0)");
    assertApproxEqRel(holderClaimAfter[1], holderClaimBefore[1], 0.001e18, "holder claim preserved (t1)");
  }

  function test_GHSA_1B_pancake_fixed_slippageDepositSucceeds_largeFees() public {
    _donatePancakeV4Fees(1 ether, 1 ether);
    token0.mint(depositor, 2 ether);
    token1.mint(depositor, 2 ether);
    vm.startPrank(depositor);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 50, 0);
    vm.stopPrank();
    assertGt(shares, 0, "slippage-guarded deposit succeeds after fees accrue");
  }

  function test_GHSA_1B_pancake_fixed_slippageDepositSucceeds_smallFees() public {
    _donatePancakeV4Fees(0.001 ether, 0.001 ether);
    token0.mint(depositor, 2 ether);
    token1.mint(depositor, 2 ether);
    vm.startPrank(depositor);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit([uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)], 50, 0);
    vm.stopPrank();
    assertGt(shares, 0, "slippage-guarded deposit succeeds after small fees accrue");
  }

  function test_GHSA_1C_pancake_fixed_swapAndIncreaseChargesFees() public {
    _setUpFeeVault();
    _donatePancakeV4Fees(1 ether, 1 ether);
    (uint256 g0,) = _uncollected(fvId);
    uint256 ownerBal0 = token0.balanceOf(vaultOwner);

    _execOn(fv, vaultOwner, _swapAndIncreaseData(fvId, 0.1 ether, 0.1 ether));

    (uint256 r0, uint256 r1) = _uncollected(fvId);
    assertEq(r0 + r1, 0, "fees collected by swapAndIncrease");
    assertApproxEqRel(token0.balanceOf(feeRecipient), g0 * PLATFORM_BPS / 10_000, 0.02e18, "platform fee paid");
    assertApproxEqRel(token0.balanceOf(vaultOwner) - ownerBal0, g0 * OWNER_BPS / 10_000, 0.02e18, "owner fee paid");
  }

  // ───────── Claim 2 (twin of the V4 planted-NFT tests): swapAndIncrease tracks the position ─────────

  function _plantOnVault(address planter, uint128 liquidity) internal returns (uint256 planted) {
    token0.mint(planter, 1 ether);
    token1.mint(planter, 1 ether);
    vm.startPrank(planter);
    token0.approve(address(permit2), type(uint256).max);
    token1.approve(address(permit2), type(uint256).max);
    permit2.approve(address(token0), BASE_PANCAKE_V4_POSM, type(uint160).max, type(uint48).max);
    permit2.approve(address(token1), BASE_PANCAKE_V4_POSM, type(uint160).max, type(uint48).max);
    bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // CL_MINT_POSITION, SETTLE_PAIR
    bytes[] memory params = new bytes[](2);
    params[0] =
      abi.encode(poolKey, TICK_LOWER, TICK_UPPER, uint256(liquidity), MAX_TOKEN_IN, MAX_TOKEN_IN, address(vault), bytes(""));
    params[1] = abi.encode(Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1));
    planted = posm.nextTokenId();
    posm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
    vm.stopPrank();
  }

  function _decreaseAllData(uint256 id) internal view returns (bytes memory) {
    IPancakeV4Utils.DecreaseAndSwapParams memory d = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: posm.getPositionLiquidity(id),
        deadline: block.timestamp + 300,
        amount0Min: 0,
        amount1Min: 0,
        hookData: ""
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      swapDestToken: Currency.wrap(address(0)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory ins =
      IPancakeV4Utils.Instructions({ action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(d) });
    return bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_PANCAKE_V4_POSM,
        id,
        abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, id, ins)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
  }

  function test_GHSA_2_pancake_fixed_swapAndIncreaseTracksPlantedNft_noNavCollapse() public {
    uint256 planted = _plantOnVault(makeAddr("planter"), 1e6);
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(planted), address(vault), "vault owns the planted NFT");
    assertEq(vault.getPositionCount(), 1, "planted NFT starts untracked");

    address admin = makeAddr("admin");
    vm.prank(vaultOwner);
    vault.grantAdminRole(admin);

    uint256[4] memory totBefore = vault.getTotalBalances();
    _execOn(vault, admin, _swapAndIncreaseData(planted, 9 ether, 9 ether));

    assertEq(vault.getPositionCount(), 2, "planted NFT is now tracked after swapAndIncrease");
    uint256[4] memory totAfter = vault.getTotalBalances();
    assertApproxEqRel(totAfter[0], totBefore[0], 0.01e18, "NAV preserved (token0) - no collapse");
    assertApproxEqRel(totAfter[1], totBefore[1], 0.01e18, "NAV preserved (token1) - no collapse");
  }

  function test_GHSA_2_pancake_fixed_fullSandwichYieldsNoProfit() public {
    uint256 planted = _plantOnVault(makeAddr("planter"), 1e6);
    address admin = makeAddr("admin");
    vm.prank(vaultOwner);
    vault.grantAdminRole(admin);

    _execOn(vault, admin, _swapAndIncreaseData(planted, 9 ether, 9 ether));

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

    _execOn(vault, admin, _decreaseAllData(planted));

    uint256[4] memory mins;
    vm.prank(colluder);
    uint256[4] memory got = vault.withdraw(shares, mins, false);

    assertLe(got[0], in0, "colluder cannot profit (token0)");
    assertLe(got[1], in1, "colluder cannot profit (token1)");
  }
}
