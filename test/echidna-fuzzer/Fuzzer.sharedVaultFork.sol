// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * SharedVault fork-mode Echidna harness.
 *
 * This is intentionally separate from Fuzzer.sharedVault.sol. The mock harness
 * is for high-volume accounting edge cases; this fork harness exercises the
 * real SharedV3Strategy, real Base Uniswap V3 NFPM, and real V3Utils path.
 *
 * ECHIDNA_RPC_URL must point at Base, not Ethereum mainnet. The constants below
 * use deployed shared-vault infrastructure from contracts-shared.json at Base
 * block 46,190,000.
 *
 * Refreshing this fork pin after a Base redeploy:
 *   1. Update BASE_SHARED_VAULT_FACTORY and BASE_SHARED_V3_STRATEGY_PROXY from
 *      contracts-shared.json for Base.
 *   2. Update BASE_FORK_BLOCK below.
 *   3. Pass the same block with --rpc-block when running Echidna.
 *
 * Example:
 *   echidna test/echidna-fuzzer/Fuzzer.sharedVaultFork.sol \
 *     --config test/echidna-fuzzer/config.sharedVaultFork.yaml \
 *     --contract SharedVaultForkFuzzer \
 *     --rpc-url "https://rpc-node-lb.krystal.app/?chain_id=8453&debug_trace_only=true" \
 *     --rpc-block 46190000
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedVaultFactory } from "../../contracts/shared-vault/interfaces/ISharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

// ─── V4 imports (Currency / PoolKey / IHooks)
// ─────────────────────────────────
// Used only by the V4 security-regression handler below. Brings in heavy type
// definitions but no per-call runtime cost beyond what's inherent to V4 calldata
// encoding.
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { ISharedV4Utils as IV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import {
  ISharedPancakeV4Utils as IPancakeV4Utils
} from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { PoolKey as PancakeV4PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency as PancakeCurrency } from "infinity-core/src/types/Currency.sol";
import { IHooks as IPancakeHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager as IPancakePoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";

interface IBaseV3Nfpm {
  function positions(uint256 tokenId)
    external
    view
    returns (
      uint96 nonce,
      address operator,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    );
}

interface IForkVm {
  function prank(address sender) external;

  function store(address target, bytes32 slot, bytes32 value) external;
}

interface IForkOwnable {
  function owner() external view returns (address);
}

/// @dev Minimal slice of the SharedVaultFactory surface needed to swap the clones'
///      implementation pointer to a locally-compiled `SharedVault`. The full interface
///      doesn't expose these (they're owner-gated admin methods).
interface IForkFactoryUpgrade {
  function vaultImplementation() external view returns (address);

  function setVaultImplementation(address newImpl) external;
}

contract SharedVaultForkPlayer {
  ISharedVault public vault;

  constructor(ISharedVault _vault, address token0, address token1) {
    vault = _vault;
    IERC20(token0).approve(address(_vault), type(uint256).max);
    IERC20(token1).approve(address(_vault), type(uint256).max);
  }

  function deposit(uint256[4] memory amounts, uint16 slippageBps) external returns (uint256 shares) {
    return vault.deposit(amounts, slippageBps);
  }

  function withdraw(uint256 shares, uint256[4] memory minAmounts) external returns (uint256[4] memory amounts) {
    return vault.withdraw(shares, minAmounts, false);
  }
}

contract ForkV4MockERC20 {
  string public name;
  string public symbol;
  uint8 public decimals = 18;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "BAL");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "BAL");
    if (allowance[from][msg.sender] != type(uint256).max) {
      require(allowance[from][msg.sender] >= amount, "ALLOW");
      allowance[from][msg.sender] -= amount;
    }
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

contract ForkSwapRouter {
  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "pull failed");
    require(IERC20(tokenOut).transfer(msg.sender, amountOut), "push failed");
  }
}

contract ForkCwpNfpm {
  mapping(uint256 => address) public ownerOf;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }
}

contract ForkCwpTarget is ISharedStrategy {
  address public immutable token0;
  address public immutable token1;

  constructor(address _token0, address _token1) {
    token0 = _token0;
    token1 = _token1;
  }

  function createPosition(address nfpm, uint256 tokenId) external view returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external view override returns (PositionChange[] memory changes) {
    if (shares == totalShares) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
    } else {
      changes = new PositionChange[](0);
    }
  }

  function collectFees(address, uint256, uint16) external override { }

  function getPositionAmounts(address, uint256) external pure override returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256)
    external
    pure
    override
    returns (uint256 amount0, uint256 amount1)
  {
    return (0, 0);
  }

  function getPositionAmountsSplit(address, uint256)
    external
    pure
    override
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    return (0, 0, 0, 0);
  }

  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (token0, token1);
  }
}

contract SharedVaultForkFuzzer {
  address internal constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
  address internal constant BASE_WETH = 0x4200000000000000000000000000000000000006;
  address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  // DAI on Base. Used purely as a NON-vault ERC20 in the donation/sweep handlers below to
  // prove that an arbitrary token transferred into the vault does not enter share pricing
  // and can be swept out cleanly by the operator.
  address internal constant BASE_DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
  address internal constant BASE_UNISWAP_V3_NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
  address internal constant BASE_SHARED_VAULT_FACTORY = 0xB20B4517a17b8f9d1806906920071FACA0c3bd26;
  address internal constant BASE_SHARED_V3_STRATEGY_PROXY = 0xC2CbEfac9423030333466c8B52B6FF4e85304a8c;
  // Uniswap V4 PositionManager on Base. Used as the `posm` in V4 strategy calls.
  // We don't need this pool to exist on the fork — the security regression handler
  // exercises the `_validateV4InputTokens` gate which fires before any V4 PM call.
  address internal constant BASE_UNISWAP_V4_POSM = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
  address internal constant BASE_PANCAKE_V4_POSM = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;

  uint256 internal constant BASE_FORK_BLOCK = 46_190_000;
  uint24 internal constant FEE_TIER = 500;
  int24 internal constant TICK_SPACING = 10;
  int24 internal constant TICK_LOWER = -887_200;
  int24 internal constant TICK_UPPER = 887_200;
  uint24 internal constant V4_LP_FEE = 3000;
  int24 internal constant V4_TICK_SPACING = 60;
  int24 internal constant V4_TICK_LOWER = -600;
  int24 internal constant V4_TICK_UPPER = 600;
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  uint256 internal constant INITIAL_WETH = 1 ether;
  uint256 internal constant INITIAL_USDC = 3000e6;
  uint256 internal constant MAX_WETH_DEPOSIT = 2 ether;
  uint256 internal constant MIN_WITHDRAW_SHARES = 1e12;

  ISharedVaultFactory public factory;
  ISharedVault public vault;
  SharedVaultForkPlayer[2] public players;
  ForkSwapRouter public forkSwapRouter;
  ForkCwpNfpm public forkCwpNfpm;
  ForkCwpTarget public forkCwpTarget;

  IForkVm internal constant vm = IForkVm(HEVM_ADDRESS);

  mapping(address => bool) internal balanceSlotKnown;
  mapping(address => uint256) internal balanceSlotOf;

  uint256 public initialTokenId;
  bool public forkReady;
  bool public fullExitChecked;
  bool public collectChecked;
  bool public cwpChecked;

  /// @dev Address of the locally-compiled SharedVault implementation the factory points at
  ///      AFTER `_upgradeVaultImplementationToLocalSource()` runs. Exposed so an assertion
  ///      handler can confirm the upgrade actually took effect.
  address public localVaultImplementation;

  // ─── V4 security-regression harness
  // ──────────────────────────────────────────
  // The Uniswap V4 strategy here is a freshly-deployed `SharedV4Strategy` linked
  // against the locally-compiled `SharedV4StrategyLib` (which carries the
  // `_validateV4InputTokens` currency-match fix). It is whitelisted into the
  // production `SharedConfigManager` so the fork vault can `execute` against it
  // via DELEGATECALL — exactly mirroring how the real deployed V4 strategy proxy
  // is invoked, but with patched bytecode.
  SharedV4Strategy public localV4Strategy;
  /// @dev Vault with THREE configured tokens: WETH (currency0 of the test pool),
  ///      USDC (currency1), and DAI (the "bait" non-pool vault token). Without a
  ///      third vault token the gas-fee siphon exploit can't even be staged —
  ///      `_validateVaultToken(DAI)` would short-circuit before the buggy
  ///      `_takeInputGasFeesAndGetPoolAmounts` step is reached.
  ISharedVault public v4ThreeTokenVault;
  bool public v4HarnessReady;
  bool public v4SecurityFiredAtLeastOnce;
  bool public v4SuccessChecked;
  bool public v4NativeSuccessChecked;

  SharedPancakeV4Strategy public localPancakeV4Strategy;
  ISharedVault public pancakeV4ThreeTokenVault;
  bool public pancakeV4HarnessReady;
  bool public pancakeV4SecurityFiredAtLeastOnce;
  bool public pancakeV4SuccessChecked;
  bool public pancakeV4NativeSuccessChecked;

  constructor() payable { }

  function _ensureBaseVault() internal {
    if (address(vault) != address(0)) return;

    factory = ISharedVaultFactory(BASE_SHARED_VAULT_FACTORY);
    _upgradeVaultImplementationToLocalSource();

    IERC20(BASE_WETH).approve(address(factory), type(uint256).max);
    IERC20(BASE_USDC).approve(address(factory), type(uint256).max);

    vault = _newInitializedVault("EchidnaForkShared");
  }

  /// @dev Replace the factory's `vaultImplementation` pointer with a freshly-deployed
  ///      `SharedVault` compiled from the current source tree. Without this the fork
  ///      harness would silently test the historical bytecode at `BASE_FORK_BLOCK`, not
  ///      whatever the repo says. Concretely this lifts in fixes like commit `fb10e44`
  ///      ("fix overpayment dust amount") that landed AFTER the on-chain implementation.
  ///      EIP-1167 clones pin the implementation at clone time, so the swap only matters
  ///      for vaults created from here on — which is exactly what `_ensureBaseVault`
  ///      and `fork_full_owner_exit_removes_real_position` do.
  function _upgradeVaultImplementationToLocalSource() internal {
    SharedVault freshImpl = new SharedVault();
    address factoryOwner = IForkOwnable(BASE_SHARED_VAULT_FACTORY).owner();
    vm.prank(factoryOwner);
    IForkFactoryUpgrade(BASE_SHARED_VAULT_FACTORY).setVaultImplementation(address(freshImpl));
    localVaultImplementation = address(freshImpl);
    assert(IForkFactoryUpgrade(BASE_SHARED_VAULT_FACTORY).vaultImplementation() == address(freshImpl));
  }

  function fork_setup_real_position() public {
    _ensureReady();
  }

  function _ensureReady() internal {
    if (forkReady) return;
    _ensureBaseVault();
    forkReady = true;

    _mintRealPosition(vault, 0.5 ether, 1500e6);
    initialTokenId = IERC721Enumerable(BASE_UNISWAP_V3_NFPM).tokenOfOwnerByIndex(address(vault), 0);

    for (uint256 i; i < players.length; i++) {
      players[i] = new SharedVaultForkPlayer(vault, BASE_WETH, BASE_USDC);
      _dealERC20(BASE_WETH, address(players[i]), 50 ether);
      _dealERC20(BASE_USDC, address(players[i]), 150_000e6);
    }

    _assertTrackedPositionOwnedByVault(vault);
    _assertShareConservation();
  }

  function fork_deposit(uint8 idx, uint256 wethAmount) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    if (vault.getPositionCount() == 0) return;

    wethAmount = _clamp(wethAmount, 1e13, MAX_WETH_DEPOSIT);
    uint256[4] memory totals = vault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256 usdcAmount = _ceilMulDiv(wethAmount, totals[1], totals[0]);
    if (usdcAmount > 20_000e6) return;

    uint256[4] memory amounts = [wethAmount, usdcAmount, uint256(0), uint256(0)];
    uint256 preview = vault.previewDeposit(amounts);
    uint256 supplyBefore = IERC20(address(vault)).totalSupply();
    uint256 sharesBefore = IERC20(address(vault)).balanceOf(address(players[idx]));

    try players[idx].deposit(amounts, 0) returns (uint256 shares) {
      assert(preview > 0);
      assert(shares > 0);
      assert(IERC20(address(vault)).totalSupply() == supplyBefore + shares);
      assert(IERC20(address(vault)).balanceOf(address(players[idx])) == sharesBefore + shares);
      assert(vault.getPositionCount() >= 1);
      _assertTrackedPositionOwnedByVault(vault);
    } catch {
      assert(preview == 0);
    }

    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  function fork_execute_call_swap(uint256 wethAmount) external {
    _ensureReady();
    if (vault.getPositionCount() == 0) return;
    _ensureForkMockTargets();

    uint256 idleWeth = IERC20(BASE_WETH).balanceOf(address(vault));
    uint256 maxIn = idleWeth / 4;
    if (maxIn < 1e13) return;

    wethAmount = _clamp(wethAmount, 1e13, maxIn);
    uint256 usdcOut = (wethAmount * 3000e6) / 1 ether;
    if (usdcOut == 0) return;

    _dealERC20(BASE_USDC, address(forkSwapRouter), usdcOut);

    uint256 wethBefore = IERC20(BASE_WETH).balanceOf(address(vault));
    uint256 usdcBefore = IERC20(BASE_USDC).balanceOf(address(vault));

    bytes memory swapCalldata = abi.encodeCall(ForkSwapRouter.swap, (BASE_WETH, BASE_USDC, wethAmount, usdcOut));
    bytes memory actionData = abi.encode(BASE_WETH, BASE_USDC, wethAmount, usdcOut, swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action({ target: address(forkSwapRouter), data: actionData, callType: ISharedCommon.CallType.CALL });
    vault.execute(actions);

    assert(IERC20(BASE_WETH).balanceOf(address(vault)) == wethBefore - wethAmount);
    assert(IERC20(BASE_USDC).balanceOf(address(vault)) == usdcBefore + usdcOut);
    assert(IERC20(BASE_WETH).allowance(address(vault), address(forkSwapRouter)) == 0);

    _assertTrackedPositionOwnedByVault(vault);
    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  function fork_execute_call_with_positions() external {
    _ensureReady();
    if (cwpChecked || vault.getPositionCount() == 0) return;
    cwpChecked = true;
    _ensureForkMockTargets();

    uint256 beforeCount = vault.getPositionCount();
    uint256 tokenId = 90_001;
    forkCwpNfpm.mint(address(vault), tokenId);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(forkCwpTarget),
      data: abi.encodeCall(ForkCwpTarget.createPosition, (address(forkCwpNfpm), tokenId)),
      callType: ISharedCommon.CallType.CALL_WITH_POSITIONS
    });
    vault.execute(actions);

    assert(vault.getPositionCount() == beforeCount + 1);
    (address strategy, address nfpm, uint256 trackedTokenId, address token0, address token1) =
      vault.getPosition(beforeCount);
    assert(strategy == address(forkCwpTarget));
    assert(nfpm == address(forkCwpNfpm));
    assert(trackedTokenId == tokenId);
    assert(token0 == BASE_WETH);
    assert(token1 == BASE_USDC);

    _assertTrackedPositionOwnedByVault(vault);
    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  function fork_withdraw(uint8 idx, uint256 shareSeed) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    uint256 balance = IERC20(address(vault)).balanceOf(address(players[idx]));
    if (balance == 0) return;

    uint256 shares = _sharesFromSeed(balance, shareSeed);
    if (shares < MIN_WITHDRAW_SHARES) return;

    uint256 supplyBefore = IERC20(address(vault)).totalSupply();
    uint256[4] memory preview = vault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;
    uint256[4] memory minAmounts;

    try players[idx].withdraw(shares, minAmounts) returns (uint256[4] memory amounts) {
      assert(_hasAnyOutput(amounts));
      assert(IERC20(address(vault)).totalSupply() == supplyBefore - shares);
      if (vault.getPositionCount() > 0) _assertTrackedPositionOwnedByVault(vault);
    } catch {
      assert(false);
    }

    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  function fork_increase_real_position(uint256 wethAmount) external {
    _ensureReady();
    if (vault.getPositionCount() == 0) return;
    uint256 tokenId = _firstTokenId(vault);
    uint128 liquidityBefore = _liquidity(tokenId);

    uint256 idleWeth = IERC20(BASE_WETH).balanceOf(address(vault));
    uint256 idleUsdc = IERC20(BASE_USDC).balanceOf(address(vault));
    if (idleWeth < 1e13 || idleUsdc < 1e6) return;

    wethAmount = _clamp(wethAmount, 1e13, idleWeth / 2);
    uint256 usdcAmount = _ceilMulDiv(wethAmount, idleUsdc, idleWeth);
    if (usdcAmount == 0 || usdcAmount > idleUsdc / 2) return;

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: BASE_SHARED_V3_STRATEGY_PROXY,
      data: _swapAndIncreaseData(tokenId, wethAmount, usdcAmount),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    vault.execute(actions);

    assert(vault.getPositionCount() >= 1);
    assert(_liquidity(tokenId) >= liquidityBefore);
    _assertTrackedPositionOwnedByVault(vault);
    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  function fork_collect_real_position() external {
    _ensureReady();
    if (collectChecked || vault.getPositionCount() == 0) return;
    collectChecked = true;

    uint256 tokenId = _firstTokenId(vault);
    IV3Utils.Instructions memory instructions = IV3Utils.Instructions({
      whatToDo: IV3Utils.WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP,
      protocol: 0,
      targetToken: address(0),
      amountRemoveMin0: 0,
      amountRemoveMin1: 0,
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      tickLower: 0,
      tickUpper: 0,
      compoundFees: false,
      liquidity: 0,
      amountAddMin0: 0,
      amountAddMin1: 0,
      deadline: block.timestamp + 300,
      recipient: address(vault),
      unwrap: false,
      liquidityFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory data = bytes.concat(abi.encode(uint8(2)), abi.encode(BASE_UNISWAP_V3_NFPM, tokenId, instructions));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: BASE_SHARED_V3_STRATEGY_PROXY, data: data, callType: ISharedCommon.CallType.DELEGATECALL
    });
    vault.execute(actions);

    assert(vault.getPositionCount() >= 1);
    _assertTrackedPositionOwnedByVault(vault);
    _assertShareConservation();
  }

  function fork_full_owner_exit_removes_real_position() external {
    _ensureReady();
    if (fullExitChecked) return;
    fullExitChecked = true;

    ISharedVault freshVault = _newInitializedVault("EchidnaForkFullExit");
    _mintRealPosition(freshVault, 0.5 ether, 1500e6);

    assert(freshVault.getPositionCount() == 1);
    uint256 shares = IERC20(address(freshVault)).balanceOf(address(this));
    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = freshVault.withdraw(shares, minAmounts, false);

    assert(withdrawn[0] > 0 || withdrawn[1] > 0);
    assert(IERC20(address(freshVault)).totalSupply() == 0);
    assert(freshVault.getPositionCount() == 0);
  }

  // ──────────────────────────────────────────────────────────────────────────────
  // Property-style handlers (each one encodes a SharedVault invariant under fuzz)
  //
  // Echidna calls these with random arguments interleaved with the existing
  // fork_deposit / fork_withdraw / fork_execute_* handlers. Each handler is
  // self-contained: it resets player balances via `_dealERC20` (which overwrites
  // via vm.store, not adds) so its measurements are unaffected by any state the
  // earlier sequence steps may have left behind. Pre-conditions are guarded with
  // `return` rather than `assert` so a guard miss simply skips the step instead
  // of wasting an Echidna sequence on a vacuous failure.
  // ──────────────────────────────────────────────────────────────────────────────

  /// @notice Property: a subsequent depositor receives shares equal to their binding-side
  ///         proportional contribution (within LP-rounding tolerance).
  /// @dev    Replaces the Foundry testFuzz_subsequentDeposit_grantsProportionalShares.
  ///         shares ≈ min(wethIn·supply/totals[0], usdcIn·supply/totals[1])
  function fork_subsequent_deposit_proportional_invariant(uint8 idx, uint256 wethSeed) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    if (vault.getPositionCount() == 0) return;

    uint256 wethIn = _clamp(wethSeed, 1e15, MAX_WETH_DEPOSIT);
    uint256[4] memory totals = vault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256 usdcIn = _ceilMulDiv(wethIn, totals[1], totals[0]);
    if (usdcIn == 0 || usdcIn > 20_000e6) return;

    uint256 supplyBefore = IERC20(address(vault)).totalSupply();

    // `_topUpERC20` adds to the player's baseline (50 ETH / 150k USDC from `_ensureReady`) so
    // subsequent handlers like `fork_deposit` still see a funded player after we run.
    _topUpERC20(BASE_WETH, address(players[idx]), wethIn);
    _topUpERC20(BASE_USDC, address(players[idx]), usdcIn);

    uint256[4] memory amounts = [wethIn, usdcIn, uint256(0), uint256(0)];
    uint256 shares;
    try players[idx].deposit(amounts, 0) returns (uint256 s) {
      shares = s;
    } catch {
      return; // ratio rounding can reject; the proportionality invariant only fires on success
    }
    if (shares == 0) return;

    uint256 expectedFromWeth = (wethIn * supplyBefore) / totals[0];
    uint256 expectedFromUsdc = (usdcIn * supplyBefore) / totals[1];
    uint256 expected = expectedFromWeth < expectedFromUsdc ? expectedFromWeth : expectedFromUsdc;

    // 1% upper bound covers LP top-up slippage on top of the binding-side floor.
    assert(_withinPct(shares, expected, 100));

    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  /// @notice Property: deposit followed by an immediate same-shares withdraw is value-preserving.
  /// @dev    Replaces the Foundry testFuzz_depositWithdrawRoundtrip_*. The single-call atomicity
  ///         means no other handler can move price between the two halves, so the only sources
  ///         of drift are LP rounding and the binding-side ratio floor.
  function fork_deposit_withdraw_roundtrip_preserves_value(uint8 idx, uint256 wethSeed) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    if (vault.getPositionCount() == 0) return;

    uint256 wethIn = _clamp(wethSeed, 1e15, MAX_WETH_DEPOSIT);
    uint256[4] memory totals = vault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256 usdcIn = _ceilMulDiv(wethIn, totals[1], totals[0]);
    if (usdcIn == 0 || usdcIn > 20_000e6) return;

    // Snapshot the player's pre-handler balance — we must NOT overwrite it (that would strand
    // subsequent `fork_deposit` handlers with a 0-balance player). Then top up additively.
    // The round-trip invariant is checked against the DELTA from this baseline.
    uint256 wethBaseline = IERC20(BASE_WETH).balanceOf(address(players[idx]));
    uint256 usdcBaseline = IERC20(BASE_USDC).balanceOf(address(players[idx]));
    _topUpERC20(BASE_WETH, address(players[idx]), wethIn);
    _topUpERC20(BASE_USDC, address(players[idx]), usdcIn);

    uint256[4] memory amounts = [wethIn, usdcIn, uint256(0), uint256(0)];
    uint256 shares;
    try players[idx].deposit(amounts, 100) returns (uint256 s) {
      shares = s;
    } catch {
      return;
    }
    if (shares == 0) return;

    uint256[4] memory minOut;
    try players[idx].withdraw(shares, minOut) {
      // Round-trip should leave the player at (baseline + wethIn) within tolerance: deposit
      // pulled wethIn, withdraw returned ≈ wethIn from the freshly burned shares.
      uint256 wethNow = IERC20(BASE_WETH).balanceOf(address(players[idx]));
      uint256 usdcNow = IERC20(BASE_USDC).balanceOf(address(players[idx]));
      uint256 wethDelta = wethNow > wethBaseline ? wethNow - wethBaseline : 0;
      uint256 usdcDelta = usdcNow > usdcBaseline ? usdcNow - usdcBaseline : 0;
      // 0.5% tolerance — matches `TOLERANCE` in the Foundry suite.
      assert(_withinPct(wethDelta, wethIn, 50));
      assert(_withinPct(usdcDelta, usdcIn, 50));
    } catch {
      // A withdraw of shares freshly minted by the *previous statement in the same call*
      // must never revert: there are no intervening price moves, no other allowances burned,
      // and the slippage guard is 0. A revert here is a real bug.
      assert(false);
    }

    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  /// @notice Property: a partial withdraw returns tokens in proportion to burnBps/10_000 of the
  ///         full-balance preview.
  /// @dev    Replaces the Foundry testFuzz_partialWithdraw_isProportionalToBurnedShares.
  function fork_partial_withdraw_is_proportional(uint8 idx, uint16 burnBps) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    uint256 balance = IERC20(address(vault)).balanceOf(address(players[idx]));
    if (balance == 0) return;

    burnBps = uint16(_clamp(uint256(burnBps), 100, 9000)); // 1% .. 90%
    uint256 burnShares = (balance * uint256(burnBps)) / 10_000;
    if (burnShares < MIN_WITHDRAW_SHARES) return;

    uint256[4] memory previewAll = vault.previewWithdraw(balance);
    uint256 expectedWeth = (previewAll[0] * uint256(burnBps)) / 10_000;
    uint256 expectedUsdc = (previewAll[1] * uint256(burnBps)) / 10_000;
    // If both preview slots are sub-dust the proportion is too noisy to measure meaningfully.
    if (expectedWeth + expectedUsdc < 100) return;

    uint256 wethBefore = IERC20(BASE_WETH).balanceOf(address(players[idx]));
    uint256 usdcBefore = IERC20(BASE_USDC).balanceOf(address(players[idx]));

    uint256[4] memory minOut;
    try players[idx].withdraw(burnShares, minOut) returns (uint256[4] memory) {
      uint256 wethBack = IERC20(BASE_WETH).balanceOf(address(players[idx])) - wethBefore;
      uint256 usdcBack = IERC20(BASE_USDC).balanceOf(address(players[idx])) - usdcBefore;
      // 1% tolerance: preview accounts for fee net-of-rate, actual withdraw collects fees first.
      // The small discrepancy between those two paths is bounded by the configured fee.
      assert(_withinPct(wethBack, expectedWeth, 100));
      assert(_withinPct(usdcBack, expectedUsdc, 100));
    } catch {
      return; // partial withdraw can validly revert (e.g. exit drops below per-token min)
    }

    _assertShareConservation();
  }

  /// @notice Property: an arbitrary ERC20 transferred into the vault NEITHER enters share pricing
  ///         NOR blocks operator sweeps. Demonstrates that the classic "donation attack"
  ///         (force-feed tokens to inflate share price) is defused by the strict vault-token
  ///         filter on getTotalBalances/previewWithdraw.
  /// @dev    Replaces the Foundry testFuzz_externalTokenDonation_thenSweep_isValueNeutral and
  ///         test_donatedNonVaultToken_cannotInflateOrDeflateOtherDepositorShares. The sweep is
  ///         performed via vm.prank(operator) because the factory-created vault's operator is
  ///         the factory owner, not this fuzzer contract.
  function fork_external_donation_then_sweep_is_value_neutral(uint256 daiSeed) external {
    _ensureReady();
    if (vault.getPositionCount() == 0) return;

    uint256 daiAmount = _clamp(daiSeed, 1, 1_000_000 ether);

    uint256[4] memory totalsBefore = vault.getTotalBalances();
    uint256 supply = IERC20(address(vault)).totalSupply();
    uint256[4] memory previewBefore = vault.previewWithdraw(supply);

    // Force-feed DAI into the vault — `_dealERC20` overwrites the balance via vm.store, so this
    // models any path that puts tokens into the contract (transfer, mint, push from any source).
    _dealERC20(BASE_DAI, address(vault), daiAmount);
    assert(IERC20(BASE_DAI).balanceOf(address(vault)) == daiAmount);

    // Share-priced state must be untouched.
    uint256[4] memory totalsMid = vault.getTotalBalances();
    uint256[4] memory previewMid = vault.previewWithdraw(supply);
    for (uint256 i; i < 4; i++) {
      assert(totalsMid[i] == totalsBefore[i]);
      assert(previewMid[i] == previewBefore[i]);
    }

    // Sweep the donation out via the operator (the factory owner on Base).
    address operator = IForkOwnable(BASE_SHARED_VAULT_FACTORY).owner();
    address recipient = address(uint160(uint256(keccak256("ECHIDNA_DONATION_RECIPIENT"))));
    uint256 recipientBefore = IERC20(BASE_DAI).balanceOf(recipient);

    address[] memory daiList = new address[](1);
    daiList[0] = BASE_DAI;
    uint256[] memory amtList = new uint256[](1);
    amtList[0] = daiAmount;

    vm.prank(operator);
    try vault.sweepTokens(daiList, amtList, recipient) {
      assert(IERC20(BASE_DAI).balanceOf(address(vault)) == 0);
      assert(IERC20(BASE_DAI).balanceOf(recipient) == recipientBefore + daiAmount);
    } catch {
      // Sweep should never fail for a non-vault token from the operator.
      assert(false);
    }

    // After the round-trip, share-priced balances are STILL untouched — sweep can never disturb
    // the vault tokens it's not configured to move.
    uint256[4] memory totalsAfter = vault.getTotalBalances();
    for (uint256 i; i < 4; i++) {
      assert(totalsAfter[i] == totalsBefore[i]);
    }
  }

  /// @notice Property: a deposit whose every slot is below the per-token min floor must revert.
  /// @dev    Replaces the Foundry testFuzz_subsequentDeposit_belowMinFloor_reverts. Bounds are
  ///         chosen so both WETH (floor = 10^(18−minTokenPrecision)) and USDC (floor = 10^(6−prec))
  ///         are strictly under-floor — there is no random seed that would push either side over.
  function fork_dust_deposit_reverts(uint8 idx, uint256 dustSeed) external {
    _ensureReady();
    idx = idx % uint8(players.length);
    if (IERC20(address(vault)).totalSupply() == 0) return;

    // WETH dust: 1 .. 1e12 wei — strictly below 1e13 floor at minTokenPrecision=5.
    uint256 dustWeth = _clamp(dustSeed, 1, 1e12);
    // USDC dust: 0 .. 5 base units — strictly below 10-unit floor.
    uint256 dustUsdc = _clamp(dustSeed >> 64, 0, 5);

    // Top-up (additive). The dust amounts are tiny so they don't measurably affect any
    // subsequent handler's view of player balances, but they DO guarantee the deposit will
    // reach the floor check rather than reverting earlier on insufficient balance.
    _topUpERC20(BASE_WETH, address(players[idx]), dustWeth);
    _topUpERC20(BASE_USDC, address(players[idx]), dustUsdc);

    uint256[4] memory amounts = [dustWeth, dustUsdc, uint256(0), uint256(0)];

    uint256 supplyBefore = IERC20(address(vault)).totalSupply();
    bool reverted = false;
    try players[idx].deposit(amounts, 0) {
    // success path — should not happen under these bounds; flag it.
    }
    catch {
      reverted = true;
    }
    assert(reverted);
    // Belt-and-suspenders: even if (hypothetically) the deposit silently succeeded, share supply
    // must not move when both sides are under-floor.
    assert(IERC20(address(vault)).totalSupply() == supplyBefore);
  }

  /// @notice Property: SWAP_AND_MINT with any reasonable amount split succeeds and adds exactly
  ///         one tracked position with non-zero NFPM liquidity.
  /// @dev    Replaces the Foundry testFuzz_swapAndMint_acceptsAnyValidAmountSplit. The handler
  ///         caps the new-position count to avoid making _assertTrackedPositionOwnedByVault's
  ///         O(n) scan slow down later sequence steps.
  function fork_swap_and_mint_random_split(uint256 wethSeed, uint256 usdcSeed) external {
    _ensureReady();
    if (vault.getPositionCount() >= 5) return; // bound the position set

    uint256 idleWeth = IERC20(BASE_WETH).balanceOf(address(vault));
    uint256 idleUsdc = IERC20(BASE_USDC).balanceOf(address(vault));
    if (idleWeth < 2e14 || idleUsdc < 2e5) return;

    // Use at most half of idle and leave at least 1 wei buffer so the strategy's safeTransferFrom
    // never hits a tight balance-edge round in the NFPM.
    uint256 wethAmount = _clamp(wethSeed, 1e14, idleWeth / 2);
    uint256 usdcAmount = _clamp(usdcSeed, 1e5, idleUsdc / 2);

    uint256 countBefore = vault.getPositionCount();

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: BASE_SHARED_V3_STRATEGY_PROXY,
      data: _swapAndMintData(wethAmount, usdcAmount),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    try vault.execute(actions) {
      // A position must have been created and tracked.
      assert(vault.getPositionCount() == countBefore + 1);
      uint256 newTokenId = IERC721Enumerable(BASE_UNISWAP_V3_NFPM).tokenOfOwnerByIndex(address(vault), countBefore);
      assert(_liquidity(newTokenId) > 0);
      _assertTrackedPositionOwnedByVault(vault);
    } catch {
      // Some amount combinations can validly fail (e.g. swap router slippage at this fork block);
      // those are not violations of the property — they're skipped operations.
      return;
    }

    _assertShareConservation();
    _assertVaultBacked(vault);
  }

  // ──────────────────────────────────────────────────────────────────────────────
  // V4 strategy security-regression harness
  //
  // The Uniswap V4 strategy library used to validate `inputTokens[i]` only as
  // "must be a configured vault token". A malicious-but-authorized executor could
  // therefore include e.g. DAI inside a WETH/USDC `swapAndMint` with a nonzero
  // `gasFeeX64` and have `_takeInputGasFeesAndGetPoolAmounts` siphon
  // `amount * gasFeeX64 / Q64` of that DAI to `msg.sender` BEFORE the per-entry
  // currency match — the remainder then silently dropped from LP accounting.
  //
  // After the fix in `SharedV4StrategyLib._validateV4InputTokens`, every
  // positive-amount entry must equal `currency0` or `currency1`. The handler
  // below builds exactly that exploit shape against a freshly deployed
  // (patched-lib-linked) `SharedV4Strategy` and asserts the call reverts with
  // `InvalidPoolTokens` AND that no vault DAI was siphoned to msg.sender.
  // ──────────────────────────────────────────────────────────────────────────────

  /// @notice Property: SwapAndMint with a non-pool vault token in `inputTokens`
  ///         reverts at the validator gate AND moves zero DAI out of the vault.
  /// @dev    The pool itself (WETH/USDC V4) does not need to exist on the fork
  ///         for this to pass — `_validateV4InputTokens` fires before any V4 PM
  ///         call. We sweep `gasFeeSeed` across the full uint64 space so Echidna
  ///         can probe both small and near-100% fee rates; any non-zero rate
  ///         used to cause a siphon, so reverting under all of them proves the
  ///         fix isn't bypassable via fee-rate edge cases.
  function fork_v4_swapAndMint_rejects_non_pool_input_token(uint64 gasFeeSeed) external {
    _ensureV4Harness();

    // Force gas fee to be non-zero: zero gas fee would skip the buggy branch
    // entirely and we'd be testing a different (uninteresting) path.
    uint64 gasFeeX64 = uint64(_clamp(uint256(gasFeeSeed), 1, type(uint64).max));

    uint256 daiVaultBefore = IERC20(BASE_DAI).balanceOf(address(v4ThreeTokenVault));
    uint256 daiAttackerBefore = IERC20(BASE_DAI).balanceOf(address(this));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(localV4Strategy),
      data: _v4SwapAndMintBaitCalldata(gasFeeX64),
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    bool reverted = false;
    try v4ThreeTokenVault.execute(actions) {
    // Reaching here means the validator gate DID NOT reject the bait DAI —
    // i.e. the fix regressed. The accompanying balance asserts below would
    // also fire under any gasFeeX64 > 0, but flagging `reverted == false`
    // first makes the failure mode obvious in Echidna's shrunk output.
    }
    catch {
      reverted = true;
    }
    assert(reverted);

    // Belt-and-suspenders: even if (hypothetically) the validator stopped
    // reverting but the rest of the flow rolled back, no DAI should have moved.
    // A non-zero delta here proves a real siphon happened.
    assert(IERC20(BASE_DAI).balanceOf(address(v4ThreeTokenVault)) == daiVaultBefore);
    assert(IERC20(BASE_DAI).balanceOf(address(this)) == daiAttackerBefore);

    v4SecurityFiredAtLeastOnce = true;
  }

  function fork_v4_swapAndMint_success_with_local_pool() external {
    if (v4SuccessChecked) return;
    v4SuccessChecked = true;
    _ensureV4Harness();

    (ForkV4MockERC20 token0, ForkV4MockERC20 token1) = _deploySortedForkV4TokenPair();
    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: V4_LP_FEE,
      tickSpacing: V4_TICK_SPACING,
      hooks: IHooks(address(0))
    });
    IPositionManager(BASE_UNISWAP_V4_POSM).initializePool(key, SQRT_PRICE_1_1);

    SharedVault successVault =
      _newLocalV4Vault(address(token0), address(token1), address(localV4Strategy), BASE_UNISWAP_V4_POSM);

    uint256 nextIdBefore = IPositionManager(BASE_UNISWAP_V4_POSM).nextTokenId();

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_UNISWAP_V4_POSM,
      poolKey: key,
      mintParams: IV4Utils.MintParams({
        tickLower: V4_TICK_LOWER,
        tickUpper: V4_TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeLocalV4(
      successVault,
      address(localV4Strategy),
      _v4ExecuteData(BASE_UNISWAP_V4_POSM, 0, abi.encodeCall(IV4Utils.swapAndMint, (mintParams)))
    );

    assert(successVault.getPositionCount() == 1);
    assert(IERC721(BASE_UNISWAP_V4_POSM).ownerOf(nextIdBefore) == address(successVault));
    assert(IPositionManager(BASE_UNISWAP_V4_POSM).getPositionLiquidity(nextIdBefore) > 0);
  }

  function fork_v4_swapAndMint_native_success_with_local_pool() external {
    if (v4NativeSuccessChecked) return;
    v4NativeSuccessChecked = true;
    _ensureV4Harness();

    ForkV4MockERC20 token1 = new ForkV4MockERC20("Fork V4 Native Pair", "FV4N");
    PoolKey memory key = PoolKey({
      currency0: Currency.wrap(address(0)),
      currency1: Currency.wrap(address(token1)),
      fee: V4_LP_FEE,
      tickSpacing: V4_TICK_SPACING,
      hooks: IHooks(address(0))
    });
    IPositionManager(BASE_UNISWAP_V4_POSM).initializePool(key, SQRT_PRICE_1_1);

    SharedVault successVault = _newLocalV4NativeVault(address(token1), address(localV4Strategy), BASE_UNISWAP_V4_POSM);
    uint256 nextIdBefore = IPositionManager(BASE_UNISWAP_V4_POSM).nextTokenId();

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_UNISWAP_V4_POSM,
      poolKey: key,
      mintParams: IV4Utils.MintParams({
        tickLower: V4_TICK_LOWER,
        tickUpper: V4_TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeLocalV4(
      successVault,
      address(localV4Strategy),
      _v4ExecuteData(BASE_UNISWAP_V4_POSM, 0, abi.encodeCall(IV4Utils.swapAndMint, (mintParams)))
    );

    assert(successVault.getPositionCount() == 1);
    assert(IERC721(BASE_UNISWAP_V4_POSM).ownerOf(nextIdBefore) == address(successVault));
    assert(IPositionManager(BASE_UNISWAP_V4_POSM).getPositionLiquidity(nextIdBefore) > 0);
    (,, uint256 trackedId, address tracked0, address tracked1) = successVault.getPosition(0);
    assert(trackedId == nextIdBefore);
    assert(tracked0 == BASE_WETH);
    assert(tracked1 == address(token1));
    assert(address(successVault).balance == 0);
  }

  function fork_pancake_v4_swapAndMint_rejects_non_pool_input_token(uint64 gasFeeSeed) external {
    _ensurePancakeV4Harness();

    uint64 gasFeeX64 = uint64(_clamp(uint256(gasFeeSeed), 1, type(uint64).max));
    uint256 daiVaultBefore = IERC20(BASE_DAI).balanceOf(address(pancakeV4ThreeTokenVault));
    uint256 daiAttackerBefore = IERC20(BASE_DAI).balanceOf(address(this));

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(localPancakeV4Strategy),
      data: _pancakeV4SwapAndMintBaitCalldata(gasFeeX64),
      callType: ISharedCommon.CallType.DELEGATECALL
    });

    bool reverted = false;
    try pancakeV4ThreeTokenVault.execute(actions) { }
    catch {
      reverted = true;
    }
    assert(reverted);
    assert(IERC20(BASE_DAI).balanceOf(address(pancakeV4ThreeTokenVault)) == daiVaultBefore);
    assert(IERC20(BASE_DAI).balanceOf(address(this)) == daiAttackerBefore);

    pancakeV4SecurityFiredAtLeastOnce = true;
  }

  function fork_pancake_v4_swapAndMint_success_with_local_pool() external {
    if (pancakeV4SuccessChecked) return;
    pancakeV4SuccessChecked = true;
    _ensurePancakeV4Harness();

    (ForkV4MockERC20 token0, ForkV4MockERC20 token1) = _deploySortedForkV4TokenPair();
    address poolManager = address(ICLPositionManager(BASE_PANCAKE_V4_POSM).clPoolManager());
    PancakeV4PoolKey memory key = PancakeV4PoolKey({
      currency0: PancakeCurrency.wrap(address(token0)),
      currency1: PancakeCurrency.wrap(address(token1)),
      hooks: IPancakeHooks(address(0)),
      poolManager: IPancakePoolManager(poolManager),
      fee: V4_LP_FEE,
      parameters: _pancakeClParameters(V4_TICK_SPACING)
    });
    ICLPoolManager(poolManager).initialize(key, SQRT_PRICE_1_1);

    SharedVault successVault =
      _newLocalV4Vault(address(token0), address(token1), address(localPancakeV4Strategy), BASE_PANCAKE_V4_POSM);

    uint256 nextIdBefore = ICLPositionManager(BASE_PANCAKE_V4_POSM).nextTokenId();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: key,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: V4_TICK_LOWER,
        tickUpper: V4_TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new PancakeCurrency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeLocalV4(
      successVault,
      address(localPancakeV4Strategy),
      _pancakeV4ExecuteData(BASE_PANCAKE_V4_POSM, 0, abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)))
    );

    assert(successVault.getPositionCount() == 1);
    assert(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(nextIdBefore) == address(successVault));
    assert(ICLPositionManager(BASE_PANCAKE_V4_POSM).getPositionLiquidity(nextIdBefore) > 0);
  }

  function fork_pancake_v4_swapAndMint_native_success_with_local_pool() external {
    if (pancakeV4NativeSuccessChecked) return;
    pancakeV4NativeSuccessChecked = true;
    _ensurePancakeV4Harness();

    ForkV4MockERC20 token1 = new ForkV4MockERC20("Fork Pancake V4 Native Pair", "FPV4N");
    address poolManager = address(ICLPositionManager(BASE_PANCAKE_V4_POSM).clPoolManager());
    PancakeV4PoolKey memory key = PancakeV4PoolKey({
      currency0: PancakeCurrency.wrap(address(0)),
      currency1: PancakeCurrency.wrap(address(token1)),
      hooks: IPancakeHooks(address(0)),
      poolManager: IPancakePoolManager(poolManager),
      fee: V4_LP_FEE,
      parameters: _pancakeClParameters(V4_TICK_SPACING)
    });
    ICLPoolManager(poolManager).initialize(key, SQRT_PRICE_1_1);

    SharedVault successVault =
      _newLocalV4NativeVault(address(token1), address(localPancakeV4Strategy), BASE_PANCAKE_V4_POSM);
    uint256 nextIdBefore = ICLPositionManager(BASE_PANCAKE_V4_POSM).nextTokenId();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(address(0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: key,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: V4_TICK_LOWER,
        tickUpper: V4_TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new PancakeCurrency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeLocalV4(
      successVault,
      address(localPancakeV4Strategy),
      _pancakeV4ExecuteData(BASE_PANCAKE_V4_POSM, 0, abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)))
    );

    assert(successVault.getPositionCount() == 1);
    assert(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(nextIdBefore) == address(successVault));
    assert(ICLPositionManager(BASE_PANCAKE_V4_POSM).getPositionLiquidity(nextIdBefore) > 0);
    (,, uint256 trackedId, address tracked0, address tracked1) = successVault.getPosition(0);
    assert(trackedId == nextIdBefore);
    assert(tracked0 == BASE_WETH);
    assert(tracked1 == address(token1));
    assert(address(successVault).balance == 0);
  }

  function _ensureV4Harness() internal {
    if (v4HarnessReady) return;
    _ensureBaseVault(); // makes sure the factory points at the local SharedVault impl

    // Deploy a fresh V4 strategy. Re-deploying from local source forces a fresh
    // `SharedV4StrategyLib` deployment (since the lib is `external`), so this
    // strategy is guaranteed to use the patched validator regardless of what's
    // live on Base mainnet. Reuse the existing ForkSwapRouter as the strategy's
    // immutable swap router; the security handler never reaches the swap leg.
    if (address(forkSwapRouter) == address(0)) forkSwapRouter = new ForkSwapRouter();
    localV4Strategy = new SharedV4Strategy(address(forkSwapRouter));

    // Whitelist the strategy + V4 POSM. The vault's `execute()` rejects
    // non-whitelisted targets via `SharedStrategyGuards` inside the strategy.
    ISharedConfigManager cm = vault.configManager();
    address cmOwner = IForkOwnable(address(cm)).owner();

    address[] memory targets = new address[](1);
    targets[0] = address(localV4Strategy);
    vm.prank(cmOwner);
    cm.setWhitelistTargets(targets, true);
    assert(cm.isWhitelistedTarget(address(localV4Strategy)));

    if (!cm.isWhitelistedNfpm(BASE_UNISWAP_V4_POSM)) {
      address[] memory nfpms = new address[](1);
      nfpms[0] = BASE_UNISWAP_V4_POSM;
      vm.prank(cmOwner);
      cm.setWhitelistNfpms(nfpms, true);
    }
    assert(cm.isWhitelistedNfpm(BASE_UNISWAP_V4_POSM));

    // Mint a fresh three-token vault [WETH, USDC, DAI]. DAI is the "bait" — the
    // exploit needs it to be a configured vault token to even reach the gas-fee
    // siphon path; without that slot, `_validateVaultToken(DAI)` rejects first.
    v4ThreeTokenVault = _newV4ThreeTokenVault();
    assert(v4ThreeTokenVault.isVaultToken(BASE_DAI));

    v4HarnessReady = true;
  }

  function _ensurePancakeV4Harness() internal {
    if (pancakeV4HarnessReady) return;
    _ensureBaseVault();

    if (address(forkSwapRouter) == address(0)) forkSwapRouter = new ForkSwapRouter();
    localPancakeV4Strategy = new SharedPancakeV4Strategy(address(forkSwapRouter));

    ISharedConfigManager cm = vault.configManager();
    address cmOwner = IForkOwnable(address(cm)).owner();

    address[] memory targets = new address[](1);
    targets[0] = address(localPancakeV4Strategy);
    vm.prank(cmOwner);
    cm.setWhitelistTargets(targets, true);
    assert(cm.isWhitelistedTarget(address(localPancakeV4Strategy)));

    if (!cm.isWhitelistedNfpm(BASE_PANCAKE_V4_POSM)) {
      address[] memory nfpms = new address[](1);
      nfpms[0] = BASE_PANCAKE_V4_POSM;
      vm.prank(cmOwner);
      cm.setWhitelistNfpms(nfpms, true);
    }
    assert(cm.isWhitelistedNfpm(BASE_PANCAKE_V4_POSM));

    pancakeV4ThreeTokenVault = _newPancakeV4ThreeTokenVault();
    assert(pancakeV4ThreeTokenVault.isVaultToken(BASE_DAI));

    pancakeV4HarnessReady = true;
  }

  function _newV4ThreeTokenVault() internal returns (ISharedVault v) {
    _dealERC20(BASE_WETH, address(this), INITIAL_WETH);
    _dealERC20(BASE_USDC, address(this), INITIAL_USDC);
    _dealERC20(BASE_DAI, address(this), 1000 ether);

    IERC20(BASE_DAI).approve(address(factory), type(uint256).max);

    address[4] memory tokens = [BASE_WETH, BASE_USDC, BASE_DAI, address(0)];
    uint256[4] memory initialAmounts = [INITIAL_WETH, INITIAL_USDC, uint256(1000 ether), uint256(0)];
    v = ISharedVault(factory.createVault("EchidnaForkV4Bait", tokens, initialAmounts, 0));
  }

  function _newPancakeV4ThreeTokenVault() internal returns (ISharedVault v) {
    _dealERC20(BASE_WETH, address(this), INITIAL_WETH);
    _dealERC20(BASE_USDC, address(this), INITIAL_USDC);
    _dealERC20(BASE_DAI, address(this), 1000 ether);

    IERC20(BASE_DAI).approve(address(factory), type(uint256).max);

    address[4] memory tokens = [BASE_WETH, BASE_USDC, BASE_DAI, address(0)];
    uint256[4] memory initialAmounts = [INITIAL_WETH, INITIAL_USDC, uint256(1000 ether), uint256(0)];
    v = ISharedVault(factory.createVault("EchidnaForkPancakeV4Bait", tokens, initialAmounts, 0));
  }

  function _newLocalV4Vault(address token0, address token1, address strategy, address posm)
    internal
    returns (SharedVault successVault)
  {
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = strategy;
    address[] memory nfpms = new address[](1);
    nfpms[0] = posm;
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    successVault = new SharedVault();
    ForkV4MockERC20(token0).mint(address(successVault), 10 ether);
    ForkV4MockERC20(token1).mint(address(successVault), 10 ether);
    address[4] memory tokens = [token0, token1, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    successVault.initialize(
      "EchidnaForkV4Success", tokens, initialAmounts, address(this), address(this), address(cm), token0, 0
    );
  }

  function _newLocalV4NativeVault(address token1, address strategy, address posm)
    internal
    returns (SharedVault successVault)
  {
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory targets = new address[](1);
    targets[0] = strategy;
    address[] memory nfpms = new address[](1);
    nfpms[0] = posm;
    cm.initialize(address(this), targets, new address[](0), address(this), 0, nfpms, new address[](0));

    successVault = new SharedVault();
    _dealERC20(BASE_WETH, address(successVault), 10 ether);
    ForkV4MockERC20(token1).mint(address(successVault), 10 ether);
    address[4] memory tokens = [BASE_WETH, token1, address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    successVault.initialize(
      "EchidnaForkV4NativeSuccess", tokens, initialAmounts, address(this), address(this), address(cm), BASE_WETH, 0
    );
  }

  function _executeLocalV4(SharedVault targetVault, address strategy, bytes memory stratData) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action({ target: strategy, data: stratData, callType: ISharedCommon.CallType.DELEGATECALL });
    targetVault.execute(actions);
  }

  function _v4ExecuteData(address posm, uint256 tokenId_, bytes memory paramsBytes)
    internal
    pure
    returns (bytes memory)
  {
    bytes memory innerData = abi.encode(posm, tokenId_, paramsBytes, uint256(0), new address[](0), new uint256[](0));
    return bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);
  }

  function _pancakeV4ExecuteData(address posm, uint256 tokenId_, bytes memory paramsBytes)
    internal
    pure
    returns (bytes memory)
  {
    bytes memory innerData = abi.encode(posm, tokenId_, paramsBytes, uint256(0), new address[](0), new uint256[](0));
    return bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);
  }

  function _deploySortedForkV4TokenPair() internal returns (ForkV4MockERC20 sorted0, ForkV4MockERC20 sorted1) {
    ForkV4MockERC20 a = new ForkV4MockERC20("Fork V4 A", "FV4A");
    ForkV4MockERC20 b = new ForkV4MockERC20("Fork V4 B", "FV4B");
    if (uint160(address(a)) < uint160(address(b))) return (a, b);
    return (b, a);
  }

  function _pancakeClParameters(int24 tickSpacing) internal pure returns (bytes32) {
    return bytes32(uint256(uint24(tickSpacing)) << 16);
  }

  /// @dev Builds the encoded action calldata for a `SwapAndMint` whose third
  ///      `inputTokens` entry is DAI — a vault token that is NOT one of the pool
  ///      currencies. Pre-fix this would have siphoned `daiAmount * gasFeeX64 / Q64`
  ///      DAI to `msg.sender`; post-fix it must revert at `_validateV4InputTokens`.
  function _v4SwapAndMintBaitCalldata(uint64 gasFeeX64) internal view returns (bytes memory) {
    (address c0, address c1) = BASE_WETH < BASE_USDC ? (BASE_WETH, BASE_USDC) : (BASE_USDC, BASE_WETH);

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](3);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(c0), amount: 0.01 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(c1), amount: 30e6 });
    // The exploit row: vault token, NOT a pool currency.
    inputs[2] = IV4Utils.InputTokenParams({ token: Currency.wrap(BASE_DAI), amount: 100 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_UNISWAP_V4_POSM,
      poolKey: PoolKey({
        currency0: Currency.wrap(c0),
        currency1: Currency.wrap(c1),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(0))
      }),
      mintParams: IV4Utils.MintParams({
        tickLower: -600, tickUpper: 600, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: gasFeeX64
    });

    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (mintParams));
    bytes memory innerData =
      abi.encode(BASE_UNISWAP_V4_POSM, uint256(0), paramsBytes, uint256(0), new address[](0), new uint256[](0));
    return bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);
  }

  function _pancakeV4SwapAndMintBaitCalldata(uint64 gasFeeX64) internal view returns (bytes memory) {
    (address c0, address c1) = BASE_WETH < BASE_USDC ? (BASE_WETH, BASE_USDC) : (BASE_USDC, BASE_WETH);

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(c0), amount: 0.01 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(c1), amount: 30e6 });
    inputs[2] = IPancakeV4Utils.InputTokenParams({ token: PancakeCurrency.wrap(BASE_DAI), amount: 100 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: PancakeV4PoolKey({
        currency0: PancakeCurrency.wrap(c0),
        currency1: PancakeCurrency.wrap(c1),
        hooks: IPancakeHooks(address(0)),
        poolManager: IPancakePoolManager(address(ICLPositionManager(BASE_PANCAKE_V4_POSM).clPoolManager())),
        fee: 3000,
        parameters: bytes32(uint256(uint24(60)) << 16)
      }),
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: -600, tickUpper: 600, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new PancakeCurrency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: gasFeeX64
    });

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams));
    bytes memory innerData =
      abi.encode(BASE_PANCAKE_V4_POSM, uint256(0), paramsBytes, uint256(0), new address[](0), new uint256[](0));
    return bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);
  }

  /// @notice Property: the V4 three-token vault's DAI balance equals its initial
  ///         seeding (1_000 ether). Any handler that successfully siphons DAI via
  ///         the gas-fee bait path would drop this balance — the assertion is the
  ///         post-condition counterpart to the per-call asserts in
  ///         `fork_v4_swapAndMint_rejects_non_pool_input_token`.
  function assert_fork_v4_three_token_vault_dai_untouchable() public view {
    if (!v4HarnessReady) return;
    assert(IERC20(BASE_DAI).balanceOf(address(v4ThreeTokenVault)) == 1000 ether);
  }

  function assert_fork_pancake_v4_three_token_vault_dai_untouchable() public view {
    if (!pancakeV4HarnessReady) return;
    assert(IERC20(BASE_DAI).balanceOf(address(pancakeV4ThreeTokenVault)) == 1000 ether);
  }

  function assert_fork_share_conservation() public view {
    if (!forkReady) return;
    _assertShareConservation();
  }

  /// @notice Property: the factory points at the locally-compiled SharedVault implementation
  ///         that the harness deployed in `_ensureBaseVault`. If this ever drifts, the fork
  ///         test is silently exercising historical bytecode again.
  function assert_fork_uses_local_vault_implementation() public view {
    if (!forkReady) return;
    assert(localVaultImplementation != address(0));
    assert(IForkFactoryUpgrade(BASE_SHARED_VAULT_FACTORY).vaultImplementation() == localVaultImplementation);
  }

  function assert_fork_position_owned_when_tracked() public view {
    if (!forkReady) return;
    if (vault.getPositionCount() > 0) _assertTrackedPositionOwnedByVault(vault);
  }

  function assert_fork_vault_backed() public view {
    if (!forkReady) return;
    _assertVaultBacked(vault);
  }

  function _newInitializedVault(string memory name) internal returns (ISharedVault v) {
    _dealERC20(BASE_WETH, address(this), INITIAL_WETH);
    _dealERC20(BASE_USDC, address(this), INITIAL_USDC);

    address[4] memory tokens = [BASE_WETH, BASE_USDC, address(0), address(0)];
    uint256[4] memory initialAmounts = [INITIAL_WETH, INITIAL_USDC, uint256(0), uint256(0)];
    v = ISharedVault(factory.createVault(name, tokens, initialAmounts, 0));
  }

  function _mintRealPosition(ISharedVault targetVault, uint256 amount0, uint256 amount1) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: BASE_SHARED_V3_STRATEGY_PROXY,
      data: _swapAndMintData(amount0, amount1),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    targetVault.execute(actions);
    assert(targetVault.getPositionCount() == 1);
  }

  function _ensureForkMockTargets() internal {
    if (address(forkSwapRouter) == address(0)) forkSwapRouter = new ForkSwapRouter();
    if (address(forkCwpNfpm) == address(0)) forkCwpNfpm = new ForkCwpNfpm();
    if (address(forkCwpTarget) == address(0)) forkCwpTarget = new ForkCwpTarget(BASE_WETH, BASE_USDC);

    ISharedConfigManager cm = vault.configManager();
    address cmOwner = IForkOwnable(address(cm)).owner();

    address[] memory targets = new address[](1);
    targets[0] = address(forkCwpTarget);
    vm.prank(cmOwner);
    cm.setWhitelistTargets(targets, true);

    address[] memory nfpms = new address[](1);
    nfpms[0] = address(forkCwpNfpm);
    vm.prank(cmOwner);
    cm.setWhitelistNfpms(nfpms, true);

    address[] memory swapRouters = new address[](1);
    swapRouters[0] = address(forkSwapRouter);
    vm.prank(cmOwner);
    cm.setWhitelistSwapRouters(swapRouters, true);

    assert(cm.isWhitelistedTarget(address(forkCwpTarget)));
    assert(cm.isWhitelistedNfpm(address(forkCwpNfpm)));
    assert(cm.isWhitelistedSwapRouter(address(forkSwapRouter)));
  }

  function _swapAndMintData(uint256 amount0, uint256 amount1) internal view returns (bytes memory) {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = BASE_WETH;
    approveTokens[1] = BASE_USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: BASE_UNISWAP_V3_NFPM,
      token0: BASE_WETH,
      token1: BASE_USDC,
      fee: FEE_TIER,
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

    return bytes.concat(abi.encode(uint8(0)), abi.encode(params, approveTokens, approveAmounts, uint256(0)));
  }

  function _swapAndIncreaseData(uint256 tokenId, uint256 amount0, uint256 amount1)
    internal
    view
    returns (bytes memory)
  {
    address[] memory approveTokens = new address[](2);
    approveTokens[0] = BASE_WETH;
    approveTokens[1] = BASE_USDC;

    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amount0;
    approveAmounts[1] = amount1;

    IV3Utils.SwapAndIncreaseLiquidityParams memory params = IV3Utils.SwapAndIncreaseLiquidityParams({
      protocol: 0,
      nfpm: BASE_UNISWAP_V3_NFPM,
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

    return bytes.concat(abi.encode(uint8(1)), abi.encode(params, approveTokens, approveAmounts, uint256(0)));
  }

  function _assertShareConservation() internal view {
    uint256 sum = IERC20(address(vault)).balanceOf(address(this));
    for (uint256 i; i < players.length; i++) {
      sum += IERC20(address(vault)).balanceOf(address(players[i]));
    }
    assert(sum == IERC20(address(vault)).totalSupply());
  }

  function _assertTrackedPositionOwnedByVault(ISharedVault targetVault) internal view {
    uint256 count = targetVault.getPositionCount();
    assert(count > 0);

    for (uint256 i; i < count; i++) {
      (address strategy, address nfpm, uint256 tokenId, address token0, address token1) = targetVault.getPosition(i);

      assert(token0 == BASE_WETH);
      assert(token1 == BASE_USDC);
      assert(IERC721(nfpm).ownerOf(tokenId) == address(targetVault));

      if (nfpm == BASE_UNISWAP_V3_NFPM) {
        assert(strategy == BASE_SHARED_V3_STRATEGY_PROXY);
        assert(_liquidity(tokenId) > 0);
      } else {
        assert(nfpm == address(forkCwpNfpm));
        assert(strategy == address(forkCwpTarget));
      }
    }
  }

  function _assertVaultBacked(ISharedVault targetVault) internal view {
    if (IERC20(address(targetVault)).totalSupply() == 0) return;
    uint256[4] memory totals = targetVault.getTotalBalances();
    assert(totals[0] > 0 || totals[1] > 0);
  }

  function _firstTokenId(ISharedVault targetVault) internal view returns (uint256) {
    (,, uint256 tokenId,,) = targetVault.getPosition(0);
    return tokenId;
  }

  function _liquidity(uint256 tokenId) internal view returns (uint128 liquidity) {
    (,,,,,,, liquidity,,,,) = IBaseV3Nfpm(BASE_UNISWAP_V3_NFPM).positions(tokenId);
  }

  function _dealERC20(address token, address to, uint256 amount) internal {
    uint256 slot = _balanceSlot(token);
    vm.store(token, keccak256(abi.encode(to, slot)), bytes32(amount));
    assert(IERC20(token).balanceOf(to) == amount);
  }

  /// @dev Additive variant of `_dealERC20`: increases `to`'s balance by `amount` rather than
  ///      overwriting it. Use this when topping up a player that is shared across handlers,
  ///      otherwise a subsequent handler can hit a `transferFrom` revert because the prior
  ///      handler stomped the player's baseline balance set in `_ensureReady`.
  function _topUpERC20(address token, address to, uint256 amount) internal {
    if (amount == 0) return;
    uint256 slot = _balanceSlot(token);
    uint256 current = IERC20(token).balanceOf(to);
    uint256 next = current + amount;
    vm.store(token, keccak256(abi.encode(to, slot)), bytes32(next));
    assert(IERC20(token).balanceOf(to) == next);
  }

  function _balanceSlot(address token) internal returns (uint256 slot) {
    if (balanceSlotKnown[token]) return balanceSlotOf[token];
    if (token == BASE_WETH) {
      balanceSlotKnown[token] = true;
      balanceSlotOf[token] = 3;
      return 3;
    }
    if (token == BASE_USDC) {
      balanceSlotKnown[token] = true;
      balanceSlotOf[token] = 9;
      return 9;
    }

    address probe = address(uint160(uint256(keccak256(abi.encodePacked("ECHIDNA_BALANCE_SLOT_PROBE", token)))));
    uint256 marker = 123_456_789_123_456_789;

    for (uint256 i; i < 200; i++) {
      vm.store(token, keccak256(abi.encode(probe, i)), bytes32(marker));
      if (IERC20(token).balanceOf(probe) == marker) {
        balanceSlotKnown[token] = true;
        balanceSlotOf[token] = i;
        return i;
      }
    }

    revert("BALANCE_SLOT_NOT_FOUND");
  }

  function _sharesFromSeed(uint256 balance, uint256 seed) internal pure returns (uint256 shares) {
    if (seed % 5 == 0) return balance;
    shares = seed % balance;
    if (shares == 0) shares = 1;
  }

  function _clamp(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  function _ceilMulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
    if (x == 0 || y == 0) return 0;
    return ((x * y) - 1) / d + 1;
  }

  function _hasAnyOutput(uint256[4] memory amounts) internal pure returns (bool) {
    return amounts[0] > 0 || amounts[1] > 0 || amounts[2] > 0 || amounts[3] > 0;
  }

  function _hasNonDustOutput(uint256[4] memory amounts) internal pure returns (bool) {
    return amounts[0] > 1 || amounts[1] > 1 || amounts[2] > 1 || amounts[3] > 1;
  }

  /// @dev True iff |a − b| ≤ b · maxBps / 10_000. Special-cases b == 0 so a == 0 passes any tol.
  ///      Used by the new property handlers to allow LP-rounding / preview-vs-actual drift while
  ///      still catching real proportional-share regressions.
  function _withinPct(uint256 a, uint256 b, uint256 maxBps) internal pure returns (bool) {
    if (b == 0) return a == 0;
    uint256 diff = a > b ? a - b : b - a;
    return diff * 10_000 <= b * maxBps;
  }
}
