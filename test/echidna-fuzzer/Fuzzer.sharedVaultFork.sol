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
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { ISharedVaultFactory } from "../../contracts/shared-vault/interfaces/ISharedVaultFactory.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";

interface IBaseV3Nfpm {
  function positions(
    uint256 tokenId
  )
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
  function store(address target, bytes32 slot, bytes32 value) external;
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

  function createPosition(
    address nfpm,
    uint256 tokenId
  ) external view returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override {}

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

  function collectFees(address, uint256, uint16) external override {}

  function getPositionAmounts(address, uint256) external pure override returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(
    address,
    uint256
  ) external pure override returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (token0, token1);
  }
}

contract SharedVaultForkFuzzer {
  address internal constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
  address internal constant BASE_WETH = 0x4200000000000000000000000000000000000006;
  address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address internal constant BASE_UNISWAP_V3_NFPM = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
  address internal constant BASE_SHARED_VAULT_FACTORY = 0xB20B4517a17b8f9d1806906920071FACA0c3bd26;
  address internal constant BASE_SHARED_V3_STRATEGY_PROXY = 0xC2CbEfac9423030333466c8B52B6FF4e85304a8c;

  uint256 internal constant BASE_FORK_BLOCK = 46_190_000;
  uint24 internal constant FEE_TIER = 500;
  int24 internal constant TICK_SPACING = 10;
  int24 internal constant TICK_LOWER = -887_200;
  int24 internal constant TICK_UPPER = 887_200;

  uint256 internal constant INITIAL_WETH = 1 ether;
  uint256 internal constant INITIAL_USDC = 3_000e6;
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

  constructor() payable {}

  function _ensureBaseVault() internal {
    if (address(vault) != address(0)) return;

    factory = ISharedVaultFactory(BASE_SHARED_VAULT_FACTORY);
    IERC20(BASE_WETH).approve(address(factory), type(uint256).max);
    IERC20(BASE_USDC).approve(address(factory), type(uint256).max);

    vault = _newInitializedVault("EchidnaForkShared");
  }

  function fork_setup_real_position() public {
    _ensureReady();
  }

  function _ensureReady() internal {
    if (forkReady) return;
    _ensureBaseVault();
    forkReady = true;

    _mintRealPosition(vault, 0.5 ether, 1_500e6);
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
    uint256 usdcOut = (wethAmount * 3_000e6) / 1 ether;
    if (usdcOut == 0) return;

    _dealERC20(BASE_USDC, address(forkSwapRouter), usdcOut);

    uint256 wethBefore = IERC20(BASE_WETH).balanceOf(address(vault));
    uint256 usdcBefore = IERC20(BASE_USDC).balanceOf(address(vault));

    bytes memory swapCalldata = abi.encodeCall(
      ForkSwapRouter.swap,
      (BASE_WETH, BASE_USDC, wethAmount, usdcOut)
    );
    bytes memory actionData = abi.encode(BASE_WETH, BASE_USDC, wethAmount, usdcOut, swapCalldata);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(forkSwapRouter),
      data: actionData,
      callType: ISharedCommon.CallType.CALL
    });
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
    (
      address strategy,
      address nfpm,
      uint256 trackedTokenId,
      address token0,
      address token1
    ) = vault.getPosition(beforeCount);
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

    bytes memory data = bytes.concat(
      abi.encode(uint8(2)),
      abi.encode(BASE_UNISWAP_V3_NFPM, tokenId, instructions)
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: BASE_SHARED_V3_STRATEGY_PROXY,
      data: data,
      callType: ISharedCommon.CallType.DELEGATECALL
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
    _mintRealPosition(freshVault, 0.5 ether, 1_500e6);

    assert(freshVault.getPositionCount() == 1);
    uint256 shares = IERC20(address(freshVault)).balanceOf(address(this));
    uint256[4] memory minAmounts;
    uint256[4] memory withdrawn = freshVault.withdraw(shares, minAmounts, false);

    assert(withdrawn[0] > 0 || withdrawn[1] > 0);
    assert(IERC20(address(freshVault)).totalSupply() == 0);
    assert(freshVault.getPositionCount() == 0);
  }

  function assert_fork_share_conservation() public view {
    if (!forkReady) return;
    _assertShareConservation();
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
    if (address(forkSwapRouter) == address(0)) {
      forkSwapRouter = new ForkSwapRouter();
      forkCwpNfpm = new ForkCwpNfpm();
      forkCwpTarget = new ForkCwpTarget(BASE_WETH, BASE_USDC);
    }

    address cm = address(vault.configManager());
    _setAddressBoolMapping(cm, 0, address(forkCwpTarget), true); // whitelistedTargets
    _setAddressBoolMapping(cm, 2, address(forkCwpNfpm), true); // whitelistedNfpms
    _setAddressBoolMapping(cm, 3, address(forkSwapRouter), true); // whitelistedSwapRouters
  }

  function _setAddressBoolMapping(address target, uint256 slot, address key, bool value) internal {
    vm.store(target, keccak256(abi.encode(key, slot)), bytes32(value ? uint256(1) : uint256(0)));
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

    return
      bytes.concat(
        abi.encode(uint8(0)),
        abi.encode(params, approveTokens, approveAmounts, uint256(0))
      );
  }

  function _swapAndIncreaseData(
    uint256 tokenId,
    uint256 amount0,
    uint256 amount1
  ) internal view returns (bytes memory) {
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

    return
      bytes.concat(
        abi.encode(uint8(1)),
        abi.encode(params, approveTokens, approveAmounts, uint256(0))
      );
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
    (, , uint256 tokenId, , ) = targetVault.getPosition(0);
    return tokenId;
  }

  function _liquidity(uint256 tokenId) internal view returns (uint128 liquidity) {
    (, , , , , , , liquidity, , , , ) = IBaseV3Nfpm(BASE_UNISWAP_V3_NFPM).positions(tokenId);
  }

  function _dealERC20(address token, address to, uint256 amount) internal {
    uint256 slot = _balanceSlot(token);
    vm.store(token, keccak256(abi.encode(to, slot)), bytes32(amount));
    assert(IERC20(token).balanceOf(to) == amount);
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
}
