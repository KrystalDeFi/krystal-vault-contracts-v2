// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { PoolDonateTest } from "@uniswap/v4-core/src/test/PoolDonateTest.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { IWETH9 } from "../../contracts/public-vault/interfaces/IWETH9.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { SharedV4Strategy } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";
import { ISharedV4Utils as IV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";

interface IPermit2Getter {
  function permit2() external view returns (IAllowanceTransfer);
}

contract V4ForkMockERC20 {
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

contract RecordingSwapRouter {
  bytes public lastData;
  uint256 public callCount;
  uint256 public lastAmountIn;

  function swap(address tokenIn, address tokenOut, uint256 amountOut) external {
    callCount++;
    lastData = msg.data;
    uint256 amountIn = IERC20(tokenIn).allowance(msg.sender, address(this));
    lastAmountIn = amountIn;
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    V4ForkMockERC20(tokenOut).mint(msg.sender, amountOut == 0 ? amountIn : amountOut);
  }
}

contract SharedVaultV4IntegrationTest is TestCommon {
  address internal constant BASE_V4_POSM = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
  address internal constant BASE_WETH = 0x4200000000000000000000000000000000000006;
  uint256 internal constant BASE_FORK_BLOCK = 36_953_600;
  uint24 internal constant LP_FEE = 3000;
  int24 internal constant TICK_SPACING = 60;
  int24 internal constant TICK_LOWER = -600;
  int24 internal constant TICK_UPPER = 600;
  uint128 internal constant INITIAL_LIQUIDITY = 1 ether;
  uint128 internal constant MAX_TOKEN_IN = 10 ether;
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  IPositionManager internal posm;
  IAllowanceTransfer internal permit2;
  V4ForkMockERC20 internal token0;
  V4ForkMockERC20 internal token1;
  V4ForkMockERC20 internal hopToken;
  PoolKey internal poolKey;
  SharedConfigManager internal configManager;
  SharedVault internal vault;
  SharedV4Strategy internal strategy;
  RecordingSwapRouter internal swapRouter;
  uint256 internal tokenId;

  address internal vaultOwner;
  address internal depositor;
  address internal feeRecipient;
  uint256 internal constant SWAP_DATA_SIGNER_PK = 0x5A17;
  address internal swapDataSigner;

  receive() external payable { }

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    vm.selectFork(fork);

    vaultOwner = makeAddr("vaultOwner");
    depositor = makeAddr("depositor");
    feeRecipient = makeAddr("feeRecipient");
    swapDataSigner = vm.addr(SWAP_DATA_SIGNER_PK);

    posm = IPositionManager(BASE_V4_POSM);
    permit2 = IPermit2Getter(BASE_V4_POSM).permit2();

    (token0, token1) = _deploySortedTokenPair();
    hopToken = new V4ForkMockERC20("Hop", "HOP");
    poolKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      fee: LP_FEE,
      tickSpacing: TICK_SPACING,
      hooks: IHooks(address(0))
    });
    posm.initializePool(poolKey, SQRT_PRICE_1_1);

    swapRouter = new RecordingSwapRouter();
    strategy = new SharedV4Strategy(address(swapRouter));

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = BASE_V4_POSM;
    address[] memory swapRouters = new address[](1);
    swapRouters[0] = address(swapRouter);
    configManager = new SharedConfigManager();
    address[] memory signers = new address[](1);
    signers[0] = swapDataSigner;
    configManager.initialize(address(this), targets, new address[](0), feeRecipient, 0, nfpms, swapRouters, signers);

    vault = new SharedVault();
    token0.mint(address(vault), 10 ether);
    token1.mint(address(vault), 10 ether);
    address[4] memory vaultTokens = [address(token0), address(token1), address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    vault.initialize(
      "SharedVault-V4-Fork",
      vaultTokens,
      initialAmounts,
      vaultOwner,
      address(this),
      address(configManager),
      address(token0),
      0
    );

    token0.mint(address(this), 100 ether);
    token1.mint(address(this), 100 ether);
    tokenId = _mintPositionToOperator(poolKey, 0);
    IERC721(BASE_V4_POSM).approve(address(vault), tokenId);
    vault.recoverPosition(BASE_V4_POSM, tokenId, address(strategy), address(token0), address(token1));
  }

  function test_depositProportional_usesPermit2WithRealV4PositionManager() public {
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);

    token0.mint(depositor, 100 ether);
    token1.mint(depositor, 100 ether);

    vm.startPrank(depositor);
    token0.approve(address(vault), type(uint256).max);
    token1.approve(address(vault), type(uint256).max);
    uint256[4] memory amounts = [uint256(1 ether), uint256(1 ether), uint256(0), uint256(0)];
    uint256 shares = vault.deposit(amounts, 1, 0);
    vm.stopPrank();

    assertGt(shares, 0, "deposit mints shares");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "V4 liquidity increases");
    assertEq(token0.allowance(address(vault), address(permit2)), 0, "token0 ERC20 Permit2 approval cleared");
    assertEq(token1.allowance(address(vault), address(permit2)), 0, "token1 ERC20 Permit2 approval cleared");

    (uint160 permitAmount0,,) = permit2.allowance(address(vault), address(token0), BASE_V4_POSM);
    (uint160 permitAmount1,,) = permit2.allowance(address(vault), address(token1), BASE_V4_POSM);
    assertEq(permitAmount0, 0, "token0 Permit2 POSM allowance cleared");
    assertEq(permitAmount1, 0, "token1 Permit2 POSM allowance cleared");
  }

  function test_swapAndMint_createsTrackedPositionWithRealV4PositionManager() public {
    uint256 countBefore = vault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: poolKey,
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

    _executeV4(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM,
          uint256(0),
          abi.encodeCall(IV4Utils.swapAndMint, (mintParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      )
    );

    assertEq(vault.getPositionCount(), countBefore + 1, "new V4 position tracked");
    assertEq(IERC721(BASE_V4_POSM).ownerOf(nextIdBefore), address(vault), "vault owns new V4 NFT");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new V4 liquidity");
  }

  function test_swapAndMint_nativeCurrency_usesWethVaultTokenWithRealV4PositionManager() public {
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
    address[4] memory vaultTokens = [BASE_WETH, address(token0), address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    nativeVault.initialize(
      "SharedVault-V4-Native-Fork",
      vaultTokens,
      initialAmounts,
      vaultOwner,
      address(this),
      address(configManager),
      BASE_WETH,
      0
    );

    uint256 countBefore = nativeVault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();

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

    bytes memory stratData = bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_V4_POSM,
        uint256(0),
        abi.encodeCall(IV4Utils.swapAndMint, (mintParams)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    uint256 wethBefore = IERC20(BASE_WETH).balanceOf(address(nativeVault));
    vm.prank(vaultOwner);
    nativeVault.execute(actions);

    assertEq(nativeVault.getPositionCount(), countBefore + 1, "new native V4 position tracked");
    (, address trackedNfpm, uint256 trackedId, address tracked0, address tracked1) = nativeVault.getPosition(0);
    assertEq(trackedNfpm, BASE_V4_POSM, "tracked POSM");
    assertEq(trackedId, nextIdBefore, "tracked tokenId");
    assertEq(tracked0, BASE_WETH, "native side tracked as WETH");
    assertEq(tracked1, address(token0), "tracked ERC20 side");
    assertEq(IERC721(BASE_V4_POSM).ownerOf(nextIdBefore), address(nativeVault), "vault owns new native V4 NFT");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new native V4 liquidity");
    assertLt(IERC20(BASE_WETH).balanceOf(address(nativeVault)), wethBefore, "WETH was unwrapped for settlement");
    assertEq(address(nativeVault).balance, 0, "raw native was not left in vault");
  }

  function test_swapAndMint_rejectsPoolKeyNotInitializedInPositionManagerPoolManager() public {
    PoolKey memory uninitializedKey = PoolKey({
      currency0: poolKey.currency0,
      currency1: poolKey.currency1,
      fee: LP_FEE + 1,
      tickSpacing: TICK_SPACING,
      hooks: IHooks(address(0))
    });

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: uninitializedKey,
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

    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (mintParams));
    bytes memory innerData =
      abi.encode(BASE_V4_POSM, uint256(0), paramsBytes, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedCommon.InvalidOperation.selector);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function test_swapAndIncrease_addsLiquidityToTrackedPositionWithRealV4PositionManager() public {
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);
    uint256 countBefore = vault.getPositionCount();

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });

    IV4Utils.SwapAndIncreaseParams memory incParams = IV4Utils.SwapAndIncreaseParams({
      posm: BASE_V4_POSM,
      tokenId: tokenId,
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

    _executeV4(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM,
          tokenId,
          abi.encodeCall(IV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      )
    );

    assertEq(vault.getPositionCount(), countBefore, "increase does not add tracking entry");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "V4 liquidity increases");
  }

  function test_execute_compoundNoFees_keepsTrackedPositionWithRealV4PositionManager() public {
    uint256 countBefore = vault.getPositionCount();
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeV4Instructions(
      tokenId, IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) })
    );

    assertEq(vault.getPositionCount(), countBefore, "compound does not change tracking without range change");
    assertEq(posm.getPositionLiquidity(tokenId), liquidityBefore, "no-fee compound leaves liquidity unchanged");
  }

  function test_getPositionAmounts_includesRealDonatedV4Fees() public {
    (uint256 principal0Before, uint256 principal1Before) = strategy.getPositionPrincipalAmounts(BASE_V4_POSM, tokenId);
    (uint256 amount0Before, uint256 amount1Before) = strategy.getPositionAmounts(BASE_V4_POSM, tokenId);

    assertEq(amount0Before, principal0Before, "token0 starts with no pending fees");
    assertEq(amount1Before, principal1Before, "token1 starts with no pending fees");

    _donateV4Fees(1 ether, 2 ether);

    (uint256 principal0After, uint256 principal1After) = strategy.getPositionPrincipalAmounts(BASE_V4_POSM, tokenId);
    (uint256 amount0After, uint256 amount1After) = strategy.getPositionAmounts(BASE_V4_POSM, tokenId);

    assertEq(principal0After, principal0Before, "donation does not change token0 principal");
    assertEq(principal1After, principal1Before, "donation does not change token1 principal");
    assertGt(amount0After, principal0After, "token0 real donated fees are valued");
    assertGt(amount1After, principal1After, "token1 real donated fees are valued");
  }

  function test_execute_compoundWithRealDonatedV4Fees_increasesLiquidity() public {
    _donateV4Fees(1 ether, 1 ether);

    uint256 countBefore = vault.getPositionCount();
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);

    IV4Utils.CompoundFeesParams memory compoundParams = IV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executeV4Instructions(
      tokenId, IV4Utils.Instructions({ action: IV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) })
    );

    assertEq(vault.getPositionCount(), countBefore, "compound keeps the tracked V4 position");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "real fees compound into more V4 liquidity");
  }

  function test_execute_adjustRange_replacesTrackedPositionWithRealV4PositionManager() public {
    uint256 nextIdBefore = posm.nextTokenId();

    IV4Utils.AdjustRangeParams memory adjustParams = IV4Utils.AdjustRangeParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      mintParams: IV4Utils.MintParams({
        tickLower: TICK_LOWER - TICK_SPACING,
        tickUpper: TICK_UPPER + TICK_SPACING,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0,
      compoundFees: false
    });

    _executeV4Instructions(
      tokenId, IV4Utils.Instructions({ action: IV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(adjustParams) })
    );

    assertEq(vault.getPositionCount(), 1, "range adjust replaces one tracked position");
    (,, uint256 trackedTokenId,,) = vault.getPosition(0);
    assertEq(trackedTokenId, nextIdBefore, "new V4 tokenId tracked");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "replacement V4 position has liquidity");
  }

  function test_execute_batchDecreaseAndSwapThenMint_tracksExitAndNewMintWithRealV4PositionManager() public {
    uint256 oldTokenId = tokenId;
    uint256 countBefore = vault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();
    uint128 liquidity = posm.getPositionLiquidity(oldTokenId);
    assertGt(liquidity, 0, "precondition: tracked V4 position has liquidity");

    IV4Utils.DecreaseAndSwapParams memory decParams = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: liquidity, deadline: block.timestamp + 300, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      swapDestToken: Currency.wrap(address(0)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory decreaseInstructions =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams) });
    bytes memory decreaseParams = abi.encodeCall(IV4Utils.execute, (BASE_V4_POSM, oldTokenId, decreaseInstructions));
    bytes memory decreaseData = bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(BASE_V4_POSM, oldTokenId, decreaseParams, uint256(0), new address[](0), new uint256[](0))
    );

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: poolKey,
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
    bytes memory mintData = bytes.concat(
      abi.encode(SharedV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_V4_POSM,
        uint256(0),
        abi.encodeCall(IV4Utils.swapAndMint, (mintParams)),
        uint256(0),
        new address[](0),
        new uint256[](0)
      )
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action(address(strategy), decreaseData, ISharedCommon.CallType.DELEGATECALL);
    actions[1] = ISharedVault.Action(address(strategy), mintData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(vaultOwner);
    vault.execute(actions);

    assertEq(vault.getPositionCount(), countBefore, "full exit plus mint keeps one tracked V4 position");
    assertEq(posm.getPositionLiquidity(oldTokenId), 0, "old V4 position fully exited");
    (,, uint256 trackedTokenId, address trackedToken0, address trackedToken1) = vault.getPosition(0);
    assertEq(trackedTokenId, nextIdBefore, "new V4 tokenId tracked");
    assertEq(trackedToken0, address(token0), "tracked token0");
    assertEq(trackedToken1, address(token1), "tracked token1");
    assertEq(IERC721(BASE_V4_POSM).ownerOf(nextIdBefore), address(vault), "vault owns new V4 NFT");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new V4 position has liquidity");
  }

  function test_withdrawFull_removesTrackedV4PositionWithRealPositionManager() public {
    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory minAmounts;

    vm.prank(vaultOwner);
    uint256[4] memory amounts = vault.withdraw(shares, minAmounts, false);

    assertGt(amounts[0] + amounts[1], 0, "withdraw returns pool tokens");
    assertEq(vault.totalSupply(), 0, "all shares burned");
    assertEq(vault.getPositionCount(), 0, "full V4 withdraw removes tracked position");
  }

  function test_recoverPosition_rejectsNativeCurrencyPoolFromRealV4PositionManager() public {
    PoolKey memory nativeKey = PoolKey({
      currency0: Currency.wrap(address(0)),
      currency1: Currency.wrap(address(token0)),
      fee: LP_FEE,
      tickSpacing: TICK_SPACING,
      hooks: IHooks(address(0))
    });
    posm.initializePool(nativeKey, SQRT_PRICE_1_1);

    uint256 nativeTokenId = _mintPositionToOperator(nativeKey, 10 ether);

    vm.expectRevert(ISharedCommon.TokenNotConfigured.selector);
    vault.recoverPosition(BASE_V4_POSM, nativeTokenId, address(strategy), address(0), address(token0));
  }

  function test_execute_forwardsMultiHopDecreaseAndSwapPayloadWithRealV4PositionManager() public {
    uint256 token1Before = token1.balanceOf(address(vault));
    bytes memory hop0SwapData =
      abi.encodeCall(RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether));
    bytes memory hop1SwapData =
      abi.encodeCall(RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.01 ether));

    IV4Utils.SwapParams[] memory swaps = new IV4Utils.SwapParams[](2);
    swaps[0] = IV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0.01 ether,
      tokenOut: Currency.wrap(address(hopToken)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(token0), address(hopToken), 0.01 ether, 1, hop0SwapData)
    });
    swaps[1] = IV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(hopToken)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(hopToken), address(token1), 0.01 ether, 1, hop1SwapData)
    });

    IV4Utils.DecreaseAndSwapParams memory decParams = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: Currency.wrap(address(token1)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory instructions =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (BASE_V4_POSM, tokenId, instructions));

    address[] memory approveTokens = new address[](2);
    approveTokens[0] = address(token0);
    approveTokens[1] = address(token1);
    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = 0.01 ether;
    approveAmounts[1] = 0.01 ether;

    bytes memory innerData = abi.encode(BASE_V4_POSM, tokenId, params, uint256(0), approveTokens, approveAmounts);
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(vaultOwner);
    vault.execute(actions);

    assertEq(swapRouter.callCount(), 2, "native strategy executes both swap hops");
    assertEq(keccak256(swapRouter.lastData()), keccak256(hop1SwapData), "router receives final hop payload");
    assertGt(token1.balanceOf(address(vault)), token1Before, "vault receives final hop output");
    assertEq(token0.allowance(address(vault), address(swapRouter)), 0, "token0 router approval cleared");
    assertEq(hopToken.allowance(address(vault), address(swapRouter)), 0, "hop router approval cleared");
    assertEq(token1.allowance(address(vault), address(swapRouter)), 0, "token1 router approval cleared");
    assertEq(IERC721(BASE_V4_POSM).getApproved(tokenId), address(0), "NFT approval cleared");
  }

  // =========================================================
  // Virtual ledger: a multi-hop pipeline that fails to fully consume an intermediate token
  // MUST revert. Here hop 1 produces 0.01 ether of hopToken but hop 2 only consumes 0.005 ether,
  // leaving 0.005 ether of an untracked token stranded in the vault outside TVL/share accounting.
  // =========================================================
  function test_execute_revertsWhenPipelineLeavesUnconsumedIntermediate() public {
    bytes memory hop0SwapData =
      abi.encodeCall(RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether));
    bytes memory hop1SwapData =
      abi.encodeCall(RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.005 ether));

    IV4Utils.SwapParams[] memory swaps = new IV4Utils.SwapParams[](2);
    swaps[0] = IV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0.01 ether,
      tokenOut: Currency.wrap(address(hopToken)),
      amountOutMin: 1,
      // RecordingSwapRouter mints `amountOut` of `tokenOut`; the third arg specifies the amountOut.
      // First hop produces 0.01 ether of hopToken.
      swapData: _signedSwapData(address(token0), address(hopToken), 0.01 ether, 1, hop0SwapData)
    });
    swaps[1] = IV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(hopToken)),
      amountIn: 0.005 ether, // intentionally consumes less than what hop 1 produced
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(hopToken), address(token1), 0.005 ether, 1, hop1SwapData)
    });

    IV4Utils.DecreaseAndSwapParams memory decParams = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: Currency.wrap(address(token1)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IV4Utils.Instructions memory instructions =
      IV4Utils.Instructions({ action: IV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams) });
    bytes memory params = abi.encodeCall(IV4Utils.execute, (BASE_V4_POSM, tokenId, instructions));

    bytes memory innerData = abi.encode(BASE_V4_POSM, tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  // ===========================================================================
  // Security regression: gas-fee siphon via non-pool input tokens.
  //
  // Before the fix in `_validateV4InputTokens`, an authorized executor could attach a
  // non-pool vault token (e.g. DAI on a WETH/USDC mint) inside `SwapAndMintParams.inputTokens`
  // with a nonzero `gasFeeX64`. `_takeInputGasFeesAndGetPoolAmounts` skimmed
  // `amount * gasFeeX64 / Q64` of that token BEFORE checking whether it matched `currency0`
  // or `currency1`; the unmatched amount was then silently dropped from the LP accounting.
  //
  // After the fix, every positive-amount `inputTokens[i]` must equal `currency0` or
  // `currency1`, so the path reverts with `InvalidPoolTokens()` long before the fee
  // transfer is reached. The two tests below pin that revert for swapAndMint and
  // swapAndIncrease respectively.
  // ===========================================================================

  function test_swapAndMint_rejectsNonPoolInputToken_preventsGasFeeSiphon() public {
    SharedVault threeTokenVault = _deployThreeTokenV4Vault();

    // Pre-seed the bogus non-pool vault token in the new vault. This is the token the pre-fix
    // exploit would have skimmed via the fake "gas fee" route. The amount is intentionally
    // large so that the siphoned share (at `gasFeeX64 ≈ Q64`) would be obviously material.
    hopToken.mint(address(threeTokenVault), 1 ether);

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](3);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });
    // The exploit row: a vault token that is NOT one of the pool currencies.
    inputs[2] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(hopToken)), amount: 1 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: poolKey,
      mintParams: IV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      // `Q64 / 2` ≈ 50% gas fee — well above any honest rate and large enough to make the
      // pre-fix siphon trivially observable: 0.5 ether of hopToken would have moved to the
      // executor before this test reached any LP step.
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (mintParams));
    bytes memory innerData =
      abi.encode(BASE_V4_POSM, uint256(0), paramsBytes, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    uint256 hopBefore = hopToken.balanceOf(address(threeTokenVault));
    uint256 attackerHopBefore = hopToken.balanceOf(vaultOwner);

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vm.prank(vaultOwner);
    threeTokenVault.execute(actions);

    // The whole call reverted, so no balances should have moved. We assert this explicitly to
    // distinguish a "validation rejected" outcome from a "fee was paid but later revert
    // rolled it back" outcome — only the former proves the validator is now the guard.
    assertEq(hopToken.balanceOf(address(threeTokenVault)), hopBefore, "vault hopToken untouched");
    assertEq(hopToken.balanceOf(vaultOwner), attackerHopBefore, "executor received no hopToken");
  }

  function test_swapAndIncrease_rejectsNonPoolInputToken_preventsGasFeeSiphon() public {
    SharedVault threeTokenVault = _deployThreeTokenV4Vault();

    // The vault must already own a V4 position (any tokenId) for swapAndIncrease to be
    // structurally valid. Use the same minting helper that the setUp uses.
    uint256 idForIncrease = _mintPositionToOperator(poolKey, 0);
    IERC721(BASE_V4_POSM).approve(address(threeTokenVault), idForIncrease);
    threeTokenVault.recoverPosition(BASE_V4_POSM, idForIncrease, address(strategy), address(token0), address(token1));

    hopToken.mint(address(threeTokenVault), 1 ether);

    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](3);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });
    inputs[2] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(hopToken)), amount: 1 ether });

    IV4Utils.SwapAndIncreaseParams memory incParams = IV4Utils.SwapAndIncreaseParams({
      posm: BASE_V4_POSM,
      tokenId: idForIncrease,
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndIncrease, (incParams));
    bytes memory innerData =
      abi.encode(BASE_V4_POSM, idForIncrease, paramsBytes, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vm.prank(vaultOwner);
    threeTokenVault.execute(actions);
  }

  // ===========================================================================
  // Gap coverage: dispatch guards, slippage floors, and revert-safe valuation.
  // The happy-path tests above always pass `minLiquidity: 0` and well-formed dispatch
  // envelopes, so these negative branches were previously unexercised.
  // ===========================================================================

  /// @dev `_mintV4WithAmounts` enforces `liquidity >= minLiquidity`. With an unreachable floor the
  ///      mint must revert with `InsufficientOutput` — this is the real swap-and-mint slippage guard.
  function test_swapAndMint_revertsBelowMinLiquidity() public {
    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IV4Utils.SwapAndMintParams memory mintParams = IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: poolKey,
      mintParams: IV4Utils.MintParams({
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        minLiquidity: type(uint256).max,
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

    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM,
          uint256(0),
          abi.encodeCall(IV4Utils.swapAndMint, (mintParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InsufficientOutput.selector
    );
  }

  /// @dev `_increaseV4WithAmounts` enforces `liquidity >= minLiquidity`.
  function test_swapAndIncrease_revertsBelowMinLiquidity() public {
    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });

    IV4Utils.SwapAndIncreaseParams memory incParams = IV4Utils.SwapAndIncreaseParams({
      posm: BASE_V4_POSM,
      tokenId: tokenId,
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: type(uint256).max, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM,
          tokenId,
          abi.encodeCall(IV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InsufficientOutput.selector
    );
  }

  /// @dev F8: the ADJUST_RANGE round-trip is bounded ONLY by the re-mint's `minLiquidity`. An
  ///      unreachable floor must revert the whole rebalance (the old position's burn is rolled back).
  function test_execute_adjustRange_revertsBelowMinLiquidity() public {
    IV4Utils.AdjustRangeParams memory adjustParams = IV4Utils.AdjustRangeParams({
      collectFeesHookData: "",
      swapParams: new IV4Utils.SwapParams[](0),
      mintParams: IV4Utils.MintParams({
        tickLower: TICK_LOWER - TICK_SPACING,
        tickUpper: TICK_UPPER + TICK_SPACING,
        minLiquidity: type(uint256).max,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0,
      compoundFees: false
    });

    bytes memory innerData = abi.encode(
      BASE_V4_POSM,
      tokenId,
      abi.encode(IV4Utils.Instructions({ action: IV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(adjustParams) }))
    );
    _expectRevertExecute(
      bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData),
      ISharedCommon.InsufficientOutput.selector
    );
  }

  /// @dev `_execute` rejects any non-zero `ethValue` before touching the POSM (the vault settles
  ///      native exclusively via WETH wrap/unwrap, never raw msg.value passthrough).
  function test_execute_revertsWhenEthValueNonZero() public {
    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_V4_POSM, uint256(0), paramsBytes, uint256(1), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidAmount.selector
    );
  }

  /// @dev `approveTokens.length != approveAmounts.length` is rejected up front with `LengthMismatch`.
  function test_execute_revertsOnApproveArrayLengthMismatch() public {
    address[] memory approveTokens = new address[](1);
    approveTokens[0] = address(token0);
    uint256[] memory approveAmounts = new uint256[](0);

    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_V4_POSM, uint256(0), paramsBytes, uint256(0), approveTokens, approveAmounts)
      ),
      ISharedCommon.LengthMismatch.selector
    );
  }

  /// @dev `swapAndMint` must mint a fresh position, so a non-zero outer tokenId is rejected.
  function test_swapAndMint_revertsWhenTokenIdNonZero() public {
    bytes memory paramsBytes = abi.encodeCall(IV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_V4_POSM, tokenId, paramsBytes, uint256(0), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev `swapAndIncrease` must target an existing position, so a zero outer tokenId is rejected
  ///      before the params are even decoded.
  function test_swapAndIncrease_revertsWhenTokenIdZero() public {
    IV4Utils.SwapAndIncreaseParams memory incParams = IV4Utils.SwapAndIncreaseParams({
      posm: BASE_V4_POSM,
      tokenId: tokenId,
      increaseParams: IV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IV4Utils.SwapParams[](0),
      inputTokens: new IV4Utils.InputTokenParams[](0),
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_V4_POSM,
          uint256(0),
          abi.encodeCall(IV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev A params blob whose leading selector matches none of execute/swapAndMint/swapAndIncrease
  ///      is rejected with `InvalidOperation`.
  function test_execute_revertsOnUnknownSelector() public {
    bytes memory badParams = abi.encodePacked(bytes4(0xdeadbeef));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_V4_POSM, uint256(0), badParams, uint256(0), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev Valuation must NEVER revert for an unknown/burned tokenId — `getPositionAmounts` is reached
  ///      from deposit/withdraw/preview, so a revert here would brick the whole vault. It returns zeros.
  function test_getPositionAmounts_returnsZeroForUnknownTokenId() public view {
    uint256 bogusId = posm.nextTokenId() + 1000;
    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(BASE_V4_POSM, bogusId);
    assertEq(amount0, 0, "unknown tokenId values token0 to zero");
    assertEq(amount1, 0, "unknown tokenId values token1 to zero");
    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(BASE_V4_POSM, bogusId);
    assertEq(total0 + total1 + principal0 + principal1, 0, "split valuation also zero, no revert");
  }

  /// @dev `getPositionTokens` resolves the pool currencies to the vault's sorted token pair.
  function test_getPositionTokens_returnsSortedVaultTokens() public view {
    (address t0, address t1) = strategy.getPositionTokens(BASE_V4_POSM, tokenId);
    assertEq(t0, address(token0), "token0 resolved");
    assertEq(t1, address(token1), "token1 resolved");
  }

  /// @dev Minimal valid mint params (zero floor) reused by the dispatch-guard tests whose revert
  ///      fires before the params body is ever decoded.
  function _minimalMintParams() internal view returns (IV4Utils.SwapAndMintParams memory) {
    IV4Utils.InputTokenParams[] memory inputs = new IV4Utils.InputTokenParams[](2);
    inputs[0] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });
    return IV4Utils.SwapAndMintParams({
      posm: BASE_V4_POSM,
      poolKey: poolKey,
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
  }

  function _signedSwapData(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 digest = SharedSwapDataSignature.hash(
      address(vault),
      swapDataSigner,
      address(swapRouter),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SWAP_DATA_SIGNER_PK, digest);
    return abi.encode(rawSwapData, address(vault), deadline, swapDataSigner, abi.encodePacked(r, s, v));
  }

  function _expectRevertExecute(bytes memory stratData, bytes4 expectedError) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(expectedError);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _executeV4(bytes memory stratData) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _executeV4Instructions(uint256 id, IV4Utils.Instructions memory instructions) internal {
    bytes memory innerData = abi.encode(BASE_V4_POSM, id, abi.encode(instructions));
    _executeV4(bytes.concat(abi.encode(SharedV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData));
  }

  function _donateV4Fees(uint256 amount0, uint256 amount1) internal {
    PoolDonateTest donateRouter = new PoolDonateTest(posm.poolManager());
    token0.approve(address(donateRouter), amount0);
    token1.approve(address(donateRouter), amount1);
    donateRouter.donate(poolKey, amount0, amount1, "");
  }

  /// @dev Builds a fresh `SharedVault` whose `vaultTokens` list contains `hopToken` in
  ///      addition to the pool's `token0` / `token1`. Without that third slot the exploit
  ///      can't be staged — `_validateVaultToken(hopToken)` would short-circuit. Returns the
  ///      newly initialized vault; reuses the existing `configManager`, `strategy`, and
  ///      `poolKey` from the parent `setUp`.
  function _deployThreeTokenV4Vault() internal returns (SharedVault threeTokenVault) {
    threeTokenVault = new SharedVault();
    token0.mint(address(threeTokenVault), 10 ether);
    token1.mint(address(threeTokenVault), 10 ether);
    hopToken.mint(address(threeTokenVault), 10 ether);
    address[4] memory tokens = [address(token0), address(token1), address(hopToken), address(0)];
    uint256[4] memory amounts = [uint256(10 ether), uint256(10 ether), uint256(10 ether), uint256(0)];
    threeTokenVault.initialize(
      "SharedVault-V4-3Token", tokens, amounts, vaultOwner, address(this), address(configManager), address(token0), 0
    );
  }

  function _deploySortedTokenPair() internal returns (V4ForkMockERC20 sorted0, V4ForkMockERC20 sorted1) {
    V4ForkMockERC20 a = new V4ForkMockERC20("Token A", "TKNA");
    V4ForkMockERC20 b = new V4ForkMockERC20("Token B", "TKNB");
    if (uint160(address(a)) < uint160(address(b))) return (a, b);
    return (b, a);
  }

  function _mintPositionToOperator(PoolKey memory key, uint256 nativeValue) internal returns (uint256 mintedTokenId) {
    _approveCurrencyForPosm(key.currency0);
    _approveCurrencyForPosm(key.currency1);

    bytes memory actions;
    bytes[] memory params;
    if (nativeValue == 0) {
      actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // MINT_POSITION, SETTLE_PAIR
      params = new bytes[](2);
    } else {
      actions = abi.encodePacked(uint8(0x02), uint8(0x0d), uint8(0x14)); // MINT_POSITION, SETTLE_PAIR, SWEEP
      params = new bytes[](3);
      params[2] = abi.encode(Currency.wrap(address(0)), address(this));
    }

    params[0] = abi.encode(
      key, TICK_LOWER, TICK_UPPER, INITIAL_LIQUIDITY, MAX_TOKEN_IN, MAX_TOKEN_IN, address(this), bytes("")
    );
    params[1] = abi.encode(key.currency0, key.currency1);

    mintedTokenId = posm.nextTokenId();
    posm.modifyLiquidities{ value: nativeValue }(abi.encode(actions, params), block.timestamp + 1);
    assertEq(IERC721(BASE_V4_POSM).ownerOf(mintedTokenId), address(this), "operator owns minted V4 position");
  }

  function _approveCurrencyForPosm(Currency currency) internal {
    address token = Currency.unwrap(currency);
    if (token == address(0)) return;
    IERC20(token).approve(address(permit2), type(uint256).max);
    permit2.approve(token, BASE_V4_POSM, type(uint160).max, type(uint48).max);
  }
}
