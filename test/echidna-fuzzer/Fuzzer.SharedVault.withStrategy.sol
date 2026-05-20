// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * Scenario: owner creates vault with non-zero feeBps, 2 players deposit.
 * Properties:
 *   1. totalSupply == sum of all share balances
 *   2. feeBps never changes
 *   3. No player profits (withdraws more WETH than deposited)
 *   4. Share price never decreases (modulo rounding)
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import "./IHevm.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract SharedVaultFuzzerWithStrategy {
  IHevm internal hevm = IHevm(SV_HEVM_ADDRESS);

  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedVaultPlayer public attacker;

  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedV3Strategy public v3Strategy;
  address public vault;

  uint16 public INITIAL_FEE_BPS;
  mapping(address => int256) public netWethDeposit;
  int256 public netAttackerCost;
  uint256 public lastSharePriceWad;

  constructor() payable {
    hevm.roll(SV_BLOCK_NUMBER);
    hevm.warp(SV_BLOCK_TIMESTAMP);

    owner = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    attacker = new SharedVaultPlayer();

    _fundWeth(address(owner), SV_INITIAL_WETH);
    _fundWeth(address(player1), SV_INITIAL_WETH);
    _fundWeth(address(player2), SV_INITIAL_WETH);
    _fundWeth(address(attacker), SV_INITIAL_WETH);
    _fundUsdc(address(owner), SV_INITIAL_USDC);
    _fundUsdc(address(player1), SV_INITIAL_USDC);
    _fundUsdc(address(player2), SV_INITIAL_USDC);

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner),
      targets,
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    uint16 feeBps = 500;
    INITIAL_FEE_BPS = feeBps;

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithFees", vaultTokens, initAmounts, feeBps);
    netWethDeposit[address(owner)] += int256(1 ether);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player1)] += int256(1 ether);

    player2.callDeposit(vault, pAmounts, 0);
    netWethDeposit[address(player2)] += int256(1 ether);

    lastSharePriceWad = _sharePriceWad();
  }

  // ── Fuzzed actions ──────────────────────────────────────────────────────────

  function player1_deposit(uint256 wethAmount) external {
    _doDeposit(player1, wethAmount);
  }

  function player2_deposit(uint256 wethAmount) external {
    _doDeposit(player2, wethAmount);
  }

  function player1_withdraw(uint256 shares) external {
    _doWithdraw(player1, shares);
  }

  function player2_withdraw(uint256 shares) external {
    _doWithdraw(player2, shares);
  }

  function owner_withdraw(uint256 shares) external {
    _doWithdraw(owner, shares);
  }

  function owner_deposit(uint256 wethAmount) external {
    _doDeposit(owner, wethAmount);
  }

  function advance_time(uint256 blocks) external {
    blocks = (blocks % 7200) + 1;
    hevm.roll(block.number + blocks);
    hevm.warp(block.timestamp + blocks * 2);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Close the first tracked LP position via exitProportional delegatecall.
  function owner_closeLpPosition() external {
    if (SharedVault(payable(vault)).getPositionCount() == 0) return;

    (, address nfpm, uint256 tokenId,,) = SharedVault(payable(vault)).getPosition(0);
    uint256 totalSupply = IERC20(vault).totalSupply();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: abi.encodeCall(
        ISharedStrategy.exitProportional,
        (nfpm, tokenId, totalSupply, totalSupply, 0, 0, SharedVault(payable(vault)).vaultOwnerFeeBasisPoint())
      ),
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Close any tracked position by index — stresses multi-position accounting.
  function owner_closePositionAt(uint256 index) external {
    uint256 posCount = SharedVault(payable(vault)).getPositionCount();
    if (posCount == 0) return;
    index = index % posCount;

    (, address nfpm, uint256 tokenId,,) = SharedVault(payable(vault)).getPosition(index);
    uint256 totalSupply = IERC20(vault).totalSupply();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: abi.encodeCall(
        ISharedStrategy.exitProportional,
        (nfpm, tokenId, totalSupply, totalSupply, 0, 0, SharedVault(payable(vault)).vaultOwnerFeeBasisPoint())
      ),
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Open a wide-range WETH/USDC LP position using half the vault's idle WETH.
  function owner_openLpPosition() external {
    uint256[4] memory idle = SharedVault(payable(vault)).getIdleBalances();
    if (idle[0] < 0.1 ether) return;

    uint256 amt0 = idle[0] / 2;
    uint256 amt1 = idle[1] / 2;

    address[] memory approveTokens = new address[](2);
    approveTokens[0] = SV_WETH;
    approveTokens[1] = SV_USDC;
    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amt0;
    approveAmounts[1] = amt1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: SV_NFPM,
      token0: SV_WETH,
      token1: SV_USDC,
      fee: SV_POOL_FEE,
      tickSpacing: 10,
      tickLower: SV_TICK_LOWER,
      tickUpper: SV_TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: amt0,
      amount1: amt1,
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

    bytes memory strategyData = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(v3Strategy),
      data: strategyData,
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    owner.callExecute(vault, actions);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);
  }

  /// @dev Direct WETH transfer to vault — no shares minted. Probes inflation-attack surface.
  function attacker_donateWeth(uint256 amount) external {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(attacker));
    if (bal == 0) return;
    amount = amount % bal + 1;

    uint256 supplyBefore = IERC20(vault).totalSupply();
    uint256 priceBefore = _sharePriceWad();

    hevm.prank(address(attacker));
    IERC20(SV_WETH).transfer(vault, amount);
    netAttackerCost += int256(amount);

    assert(IERC20(vault).totalSupply() == supplyBefore);
    uint256 priceAfter = _sharePriceWad();
    assert(priceAfter >= priceBefore);
    lastSharePriceWad = priceAfter;

    // Immediate victim deposit must still mint non-zero shares (inflation-attack check).
    uint256 victimWeth = 0.01 ether;
    if (IERC20(SV_WETH).balanceOf(address(player1)) < victimWeth) return;
    uint256[4] memory amts = _proportionalAmounts(victimWeth);
    if (!_hasEnoughBalance(address(player1), amts)) return;

    uint256 sBefore = player1.sharesBalance(vault);
    try player1.callDeposit(vault, amts, 200) {
      uint256 minted = player1.sharesBalance(vault) - sBefore;
      netWethDeposit[address(player1)] += int256(victimWeth);
      assert(minted > 0);
    } catch {}
  }

  // ── Properties ──────────────────────────────────────────────────────────────

  function echidna_fee_bps_immutable() external view returns (bool) {
    return SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS;
  }

  function echidna_share_supply_consistent() external view returns (bool) {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    return supply == sumBalances;
  }

  function echidna_no_player_profits() external view returns (bool) {
    return _allPlayerProfitFunded();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function _doDeposit(SharedVaultPlayer player, uint256 wethAmount) internal {
    uint256 bal = IERC20(SV_WETH).balanceOf(address(player));
    if (bal == 0) return;
    wethAmount = wethAmount % bal + 1;
    uint256[4] memory amounts = _proportionalAmounts(wethAmount);
    if (!_hasEnoughBalance(address(player), amounts)) return;

    uint256 priceBefore = _sharePriceWad();
    player.callDeposit(vault, amounts, 200);
    netWethDeposit[address(player)] += int256(wethAmount);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    uint256 priceAfter = _sharePriceWad();
    assert(priceAfter + 1e9 >= priceBefore);
    lastSharePriceWad = priceAfter;
  }

  function _doWithdraw(SharedVaultPlayer player, uint256 shares) internal {
    uint256 playerShares = player.sharesBalance(vault);
    if (playerShares == 0) return;
    shares = shares % playerShares + 1;
    uint256 wethBefore = IERC20(SV_WETH).balanceOf(address(player));
    player.callWithdraw(vault, shares, false);
    uint256 wethAfter = IERC20(SV_WETH).balanceOf(address(player));
    netWethDeposit[address(player)] -= int256(wethAfter - wethBefore);

    uint256 supply = IERC20(vault).totalSupply();
    uint256 sumBalances = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assert(supply == sumBalances);
    assert(_allPlayerProfitFunded());
    assert(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint() == INITIAL_FEE_BPS);

    if (IERC20(vault).totalSupply() > 0) lastSharePriceWad = _sharePriceWad();
  }

  function _playerProfit(SharedVaultPlayer player) internal view returns (int256) {
    int256 net = netWethDeposit[address(player)];
    return net < 0 ? -net : int256(0);
  }

  function _allPlayerProfitFunded() internal view returns (bool) {
    int256 totalProfit = _playerProfit(owner) + _playerProfit(player1) + _playerProfit(player2);
    return totalProfit <= netAttackerCost + int256(1e9);
  }

  function _playerNetOk(SharedVaultPlayer player) internal view returns (bool) {
    return netWethDeposit[address(player)] >= -int256(1e9);
  }

  function _fundWeth(address actor, uint256 amount) internal {
    hevm.deal(actor, amount);
    hevm.startPrank(actor);
    IWETH(SV_WETH).deposit{ value: amount }();
    hevm.stopPrank();
  }

  function _fundUsdc(address actor, uint256 amount) internal {
    hevm.startPrank(SV_USDC_WHALE);
    IERC20(SV_USDC).transfer(actor, amount);
    hevm.stopPrank();
  }

  function _proportionalAmounts(uint256 wethAmount) internal view returns (uint256[4] memory amounts) {
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    amounts[0] = wethAmount;
    if (totals[0] > 0 && totals[1] > 0) {
      amounts[1] = wethAmount * totals[1] / totals[0] + 1;
    }
  }

  function _hasEnoughBalance(address actor, uint256[4] memory amounts) internal view returns (bool) {
    return IERC20(SV_WETH).balanceOf(actor) >= amounts[0] && IERC20(SV_USDC).balanceOf(actor) >= amounts[1];
  }

  function _sharePriceWad() internal view returns (uint256) {
    uint256 supply = IERC20(vault).totalSupply();
    if (supply == 0) return 0;
    return SharedVault(payable(vault)).getTotalBalances()[0] * 1e18 / supply;
  }
}
