// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { IWETH9 } from "../../contracts/public-vault/interfaces/IWETH9.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { IVault as IInfinityVault } from "infinity-core/src/interfaces/IVault.sol";
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import { IPositionManagerPermit2 } from "infinity-periphery/src/interfaces/IPositionManagerPermit2.sol";
import {
  ISharedPancakeV4Utils as IPancakeV4Utils
} from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
import { CLPoolManagerRouter } from "infinity-core/test/pool-cl/helpers/CLPoolManagerRouter.sol";
import { PoolKey } from "infinity-core/src/types/PoolKey.sol";
import { Currency } from "infinity-core/src/types/Currency.sol";
import { IHooks } from "infinity-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "infinity-core/src/interfaces/IPoolManager.sol";
import { SharedPancakeV4Strategy } from "../../contracts/shared-vault/strategies/SharedPancakeV4Strategy.sol";

contract PancakeV4ForkMockERC20 {
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

contract PancakeV4RecordingSwapRouter {
  bytes public lastData;
  uint256 public callCount;
  uint256 public lastAmountIn;

  function swap(address tokenIn, address tokenOut, uint256 amountOut) external {
    callCount++;
    lastData = msg.data;
    uint256 amountIn = IERC20(tokenIn).allowance(msg.sender, address(this));
    lastAmountIn = amountIn;
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    PancakeV4ForkMockERC20(tokenOut).mint(msg.sender, amountOut == 0 ? amountIn : amountOut);
  }
}

contract SharedVaultPancakeV4IntegrationTest is TestCommon {
  address internal constant BASE_PANCAKE_V4_POSM = 0x55f4c8abA71A1e923edC303eb4fEfF14608cC226;
  address internal constant BASE_WETH = 0x4200000000000000000000000000000000000006;
  uint256 internal constant BASE_FORK_BLOCK = 36_953_600;
  uint24 internal constant LP_FEE = 3000;
  int24 internal constant TICK_SPACING = 60;
  int24 internal constant TICK_LOWER = -600;
  int24 internal constant TICK_UPPER = 600;
  uint128 internal constant INITIAL_LIQUIDITY = 1 ether;
  uint128 internal constant MAX_TOKEN_IN = 10 ether;
  uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;

  ICLPositionManager internal posm;
  ICLPoolManager internal poolManager;
  IAllowanceTransfer internal permit2;
  PancakeV4ForkMockERC20 internal token0;
  PancakeV4ForkMockERC20 internal token1;
  PancakeV4ForkMockERC20 internal hopToken;
  PoolKey internal poolKey;
  SharedConfigManager internal configManager;
  SharedVault internal vault;
  SharedPancakeV4Strategy internal strategy;
  PancakeV4RecordingSwapRouter internal swapRouter;
  uint256 internal tokenId;

  address internal vaultOwner;
  address internal depositor;
  address internal feeRecipient;
  uint256 internal constant SWAP_DATA_SIGNER_PK = 0x5A17;
  address internal swapDataSigner;
  uint256 internal swapDataNonce;

  receive() external payable { }

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    vm.selectFork(fork);

    vaultOwner = makeAddr("vaultOwner");
    depositor = makeAddr("depositor");
    feeRecipient = makeAddr("feeRecipient");
    swapDataSigner = vm.addr(SWAP_DATA_SIGNER_PK);

    posm = ICLPositionManager(BASE_PANCAKE_V4_POSM);
    poolManager = posm.clPoolManager();
    permit2 = IPositionManagerPermit2(BASE_PANCAKE_V4_POSM).permit2();

    (token0, token1) = _deploySortedTokenPair();
    hopToken = new PancakeV4ForkMockERC20("Hop", "HOP");
    poolKey = PoolKey({
      currency0: Currency.wrap(address(token0)),
      currency1: Currency.wrap(address(token1)),
      hooks: IHooks(address(0)),
      poolManager: IPoolManager(address(poolManager)),
      fee: LP_FEE,
      parameters: _clParameters(TICK_SPACING)
    });
    poolManager.initialize(poolKey, SQRT_PRICE_1_1);

    swapRouter = new PancakeV4RecordingSwapRouter();
    strategy = new SharedPancakeV4Strategy(address(swapRouter));

    address[] memory targets = new address[](1);
    targets[0] = address(strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = BASE_PANCAKE_V4_POSM;
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
      "SharedVault-PancakeV4-Fork",
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
    tokenId = _mintPositionToOperator(poolKey);
    IERC721(BASE_PANCAKE_V4_POSM).approve(address(vault), tokenId);
    vault.recoverPosition(BASE_PANCAKE_V4_POSM, tokenId, address(strategy), address(token0), address(token1));
  }

  function test_depositProportional_usesPermit2WithRealPancakeV4PositionManager() public {
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
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "Pancake V4 liquidity increases");
    assertEq(token0.allowance(address(vault), address(permit2)), 0, "token0 ERC20 Permit2 approval cleared");
    assertEq(token1.allowance(address(vault), address(permit2)), 0, "token1 ERC20 Permit2 approval cleared");

    (uint160 permitAmount0,,) = permit2.allowance(address(vault), address(token0), BASE_PANCAKE_V4_POSM);
    (uint160 permitAmount1,,) = permit2.allowance(address(vault), address(token1), BASE_PANCAKE_V4_POSM);
    assertEq(permitAmount0, 0, "token0 Permit2 POSM allowance cleared");
    assertEq(permitAmount1, 0, "token1 Permit2 POSM allowance cleared");
  }

  function test_swapAndMint_createsTrackedPositionWithRealPancakeV4PositionManager() public {
    uint256 countBefore = vault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executePancakeV4(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          uint256(0),
          abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      )
    );

    assertEq(vault.getPositionCount(), countBefore + 1, "new Pancake V4 position tracked");
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(nextIdBefore), address(vault), "vault owns new Pancake V4 NFT");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new Pancake V4 liquidity");
  }

  function test_swapAndMint_nativeCurrency_usesWethVaultTokenWithRealPancakeV4PositionManager() public {
    PoolKey memory nativeKey = PoolKey({
      currency0: Currency.wrap(address(0)),
      currency1: Currency.wrap(address(token0)),
      hooks: IHooks(address(0)),
      poolManager: IPoolManager(address(poolManager)),
      fee: LP_FEE,
      parameters: _clParameters(TICK_SPACING)
    });
    poolManager.initialize(nativeKey, SQRT_PRICE_1_1);

    SharedVault nativeVault = new SharedVault();
    vm.deal(address(this), 10 ether);
    IWETH9(BASE_WETH).deposit{ value: 10 ether }();
    IERC20(BASE_WETH).transfer(address(nativeVault), 10 ether);
    token0.mint(address(nativeVault), 10 ether);
    address[4] memory vaultTokens = [BASE_WETH, address(token0), address(0), address(0)];
    uint256[4] memory initialAmounts = [uint256(10 ether), uint256(10 ether), uint256(0), uint256(0)];
    nativeVault.initialize(
      "SharedVault-PancakeV4-Native-Fork",
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

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: nativeKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    bytes memory stratData = bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_PANCAKE_V4_POSM,
        uint256(0),
        abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)),
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

    assertEq(nativeVault.getPositionCount(), countBefore + 1, "new native Pancake V4 position tracked");
    (, address trackedNfpm, uint256 trackedId, address tracked0, address tracked1) = nativeVault.getPosition(0);
    assertEq(trackedNfpm, BASE_PANCAKE_V4_POSM, "tracked POSM");
    assertEq(trackedId, nextIdBefore, "tracked tokenId");
    assertEq(tracked0, BASE_WETH, "native side tracked as WETH");
    assertEq(tracked1, address(token0), "tracked ERC20 side");
    assertEq(
      IERC721(BASE_PANCAKE_V4_POSM).ownerOf(nextIdBefore), address(nativeVault), "vault owns native Pancake V4 NFT"
    );
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new native Pancake V4 liquidity");
    assertLt(IERC20(BASE_WETH).balanceOf(address(nativeVault)), wethBefore, "WETH was unwrapped for settlement");
    assertEq(address(nativeVault).balance, 0, "raw native was not left in vault");
  }

  function test_swapAndIncrease_addsLiquidityToTrackedPositionWithRealPancakeV4PositionManager() public {
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);
    uint256 countBefore = vault.getPositionCount();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });

    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: tokenId,
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

    _executePancakeV4(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          tokenId,
          abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      )
    );

    assertEq(vault.getPositionCount(), countBefore, "increase does not add tracking entry");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "Pancake V4 liquidity increases");
  }

  function test_execute_compoundNoFees_keepsTrackedPositionWithRealPancakeV4PositionManager() public {
    uint256 countBefore = vault.getPositionCount();
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);

    IPancakeV4Utils.CompoundFeesParams memory compoundParams = IPancakeV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executePancakeV4Instructions(
      tokenId,
      IPancakeV4Utils.Instructions({ action: IPancakeV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) })
    );

    assertEq(vault.getPositionCount(), countBefore, "compound does not change tracking without range change");
    assertEq(posm.getPositionLiquidity(tokenId), liquidityBefore, "no-fee compound leaves liquidity unchanged");
  }

  function test_getPositionAmounts_includesRealDonatedPancakeV4Fees() public {
    (uint256 principal0Before, uint256 principal1Before) =
      strategy.getPositionPrincipalAmounts(BASE_PANCAKE_V4_POSM, tokenId);
    (uint256 amount0Before, uint256 amount1Before) = strategy.getPositionAmounts(BASE_PANCAKE_V4_POSM, tokenId);

    assertEq(amount0Before, principal0Before, "token0 starts with no pending fees");
    assertEq(amount1Before, principal1Before, "token1 starts with no pending fees");

    _donatePancakeV4Fees(1 ether, 2 ether);

    (uint256 principal0After, uint256 principal1After) =
      strategy.getPositionPrincipalAmounts(BASE_PANCAKE_V4_POSM, tokenId);
    (uint256 amount0After, uint256 amount1After) = strategy.getPositionAmounts(BASE_PANCAKE_V4_POSM, tokenId);

    assertEq(principal0After, principal0Before, "donation does not change token0 principal");
    assertEq(principal1After, principal1Before, "donation does not change token1 principal");
    assertGt(amount0After, principal0After, "token0 real donated fees are valued");
    assertGt(amount1After, principal1After, "token1 real donated fees are valued");
  }

  function test_execute_compoundWithRealDonatedPancakeV4Fees_increasesLiquidity() public {
    _donatePancakeV4Fees(1 ether, 1 ether);

    uint256 countBefore = vault.getPositionCount();
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);

    IPancakeV4Utils.CompoundFeesParams memory compoundParams = IPancakeV4Utils.CompoundFeesParams({
      collectFeesHookData: "",
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _executePancakeV4Instructions(
      tokenId,
      IPancakeV4Utils.Instructions({ action: IPancakeV4Utils.UtilActions.COMPOUND, params: abi.encode(compoundParams) })
    );

    assertEq(vault.getPositionCount(), countBefore, "compound keeps the tracked Pancake V4 position");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "real fees compound into more Pancake V4 liquidity");
  }

  function test_execute_adjustRange_replacesTrackedPositionWithRealPancakeV4PositionManager() public {
    uint256 nextIdBefore = posm.nextTokenId();

    IPancakeV4Utils.AdjustRangeParams memory adjustParams = IPancakeV4Utils.AdjustRangeParams({
      collectFeesHookData: "",
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      mintParams: IPancakeV4Utils.MintParams({
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

    _executePancakeV4Instructions(
      tokenId,
      IPancakeV4Utils.Instructions({
        action: IPancakeV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(adjustParams)
      })
    );

    assertEq(vault.getPositionCount(), 1, "range adjust replaces one tracked position");
    (,, uint256 trackedTokenId,,) = vault.getPosition(0);
    assertEq(trackedTokenId, nextIdBefore, "new Pancake V4 tokenId tracked");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "replacement Pancake V4 position has liquidity");
  }

  function test_execute_batchDecreaseAndSwapThenMint_tracksExitAndNewMintWithRealPancakeV4PositionManager() public {
    uint256 oldTokenId = tokenId;
    uint256 countBefore = vault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();
    uint128 liquidity = posm.getPositionLiquidity(oldTokenId);
    assertGt(liquidity, 0, "precondition: tracked Pancake V4 position has liquidity");

    IPancakeV4Utils.DecreaseAndSwapParams memory decParams = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: liquidity, deadline: block.timestamp + 300, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      swapDestToken: Currency.wrap(address(0)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory decreaseInstructions = IPancakeV4Utils.Instructions({
      action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams)
    });
    bytes memory decreaseParams =
      abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, oldTokenId, decreaseInstructions));
    bytes memory decreaseData = bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(BASE_PANCAKE_V4_POSM, oldTokenId, decreaseParams, uint256(0), new address[](0), new uint256[](0))
    );

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    bytes memory mintData = bytes.concat(
      abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
      abi.encode(
        BASE_PANCAKE_V4_POSM,
        uint256(0),
        abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)),
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

    assertEq(vault.getPositionCount(), countBefore, "full exit plus mint keeps one tracked Pancake V4 position");
    assertEq(posm.getPositionLiquidity(oldTokenId), 0, "old Pancake V4 position fully exited");
    (,, uint256 trackedTokenId, address trackedToken0, address trackedToken1) = vault.getPosition(0);
    assertEq(trackedTokenId, nextIdBefore, "new Pancake V4 tokenId tracked");
    assertEq(trackedToken0, address(token0), "tracked token0");
    assertEq(trackedToken1, address(token1), "tracked token1");
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(nextIdBefore), address(vault), "vault owns new Pancake V4 NFT");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "new Pancake V4 position has liquidity");
  }

  function test_withdrawFull_removesTrackedPancakeV4PositionWithRealPositionManager() public {
    uint256 shares = vault.balanceOf(vaultOwner);
    uint256[4] memory minAmounts;

    vm.prank(vaultOwner);
    uint256[4] memory amounts = vault.withdraw(shares, minAmounts, false);

    assertGt(amounts[0] + amounts[1], 0, "withdraw returns pool tokens");
    assertEq(vault.totalSupply(), 0, "all shares burned");
    assertEq(vault.getPositionCount(), 0, "full Pancake V4 withdraw removes tracked position");
  }

  function test_execute_forwardsMultiHopDecreaseAndSwapPayloadWithRealPancakeV4PositionManager() public {
    uint256 token1Before = token1.balanceOf(address(vault));
    bytes memory hop0SwapData =
      abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether));
    bytes memory hop1SwapData =
      abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.01 ether));

    IPancakeV4Utils.SwapParams[] memory swaps = new IPancakeV4Utils.SwapParams[](2);
    swaps[0] = IPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0.01 ether,
      tokenOut: Currency.wrap(address(hopToken)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(token0), address(hopToken), 0.01 ether, 1, hop0SwapData)
    });
    swaps[1] = IPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(hopToken)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(hopToken), address(token1), 0, 1, hop1SwapData)
    });

    IPancakeV4Utils.DecreaseAndSwapParams memory decParams = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: Currency.wrap(address(token1)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory instructions = IPancakeV4Utils.Instructions({
      action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams)
    });
    bytes memory params = abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, tokenId, instructions));
    bytes memory innerData =
      abi.encode(BASE_PANCAKE_V4_POSM, tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

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
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).getApproved(tokenId), address(0), "NFT approval cleared");
  }

  // =========================================================
  // Virtual ledger: parallels the Uniswap V4 test — leftover intermediate must revert so untracked
  // value cannot be stranded in the vault.
  // =========================================================
  function test_execute_revertsWhenPipelineLeavesUnconsumedIntermediate() public {
    bytes memory hop0SwapData =
      abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether));
    bytes memory hop1SwapData =
      abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.005 ether));

    IPancakeV4Utils.SwapParams[] memory swaps = new IPancakeV4Utils.SwapParams[](2);
    swaps[0] = IPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0.01 ether,
      tokenOut: Currency.wrap(address(hopToken)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(token0), address(hopToken), 0.01 ether, 1, hop0SwapData)
    });
    swaps[1] = IPancakeV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(hopToken)),
      amountIn: 0.005 ether, // hop 1 produced 0.01 ether; consuming only half leaves leftover
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: 1,
      swapData: _signedSwapData(address(hopToken), address(token1), 0.005 ether, 1, hop1SwapData)
    });

    IPancakeV4Utils.DecreaseAndSwapParams memory decParams = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: Currency.wrap(address(token1)),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory instructions = IPancakeV4Utils.Instructions({
      action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP, params: abi.encode(decParams)
    });
    bytes memory params = abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, tokenId, instructions));
    bytes memory innerData =
      abi.encode(BASE_PANCAKE_V4_POSM, tokenId, params, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedCommon.InvalidAmount.selector);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  // ===========================================================================
  // Security regression: gas-fee siphon via non-pool input tokens.
  //
  // Mirrors the Uniswap V4 regression in Integration.SharedVault.V4.t.sol. Before the fix in
  // `SharedPancakeV4StrategyLib._validateV4InputTokens`, an authorized executor could attach a
  // non-pool vault token inside `SwapAndMintParams.inputTokens` with a nonzero `gasFeeX64` and
  // have `_takeInputGasFeesAndGetPoolAmounts` skim `amount * gasFeeX64 / Q64` of that token before
  // the per-entry currency check — the remainder then dropped silently from
  // the LP accounting. After the fix, every positive-amount input must match `currency0` or
  // `currency1`, so the path reverts with `InvalidPoolTokens()` before any fee transfer.
  // ===========================================================================

  function test_swapAndMint_rejectsNonPoolInputToken_preventsGasFeeSiphon() public {
    SharedVault threeTokenVault = _deployThreeTokenPancakeV4Vault();
    hopToken.mint(address(threeTokenVault), 1 ether);

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });
    inputs[2] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(hopToken)), amount: 1 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams));
    bytes memory innerData =
      abi.encode(BASE_PANCAKE_V4_POSM, uint256(0), paramsBytes, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    uint256 hopBefore = hopToken.balanceOf(address(threeTokenVault));
    uint256 attackerHopBefore = hopToken.balanceOf(vaultOwner);

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vm.prank(vaultOwner);
    threeTokenVault.execute(actions);

    assertEq(hopToken.balanceOf(address(threeTokenVault)), hopBefore, "vault hopToken untouched");
    assertEq(hopToken.balanceOf(vaultOwner), attackerHopBefore, "executor received no hopToken");
  }

  function test_swapAndIncrease_rejectsNonPoolInputToken_preventsGasFeeSiphon() public {
    SharedVault threeTokenVault = _deployThreeTokenPancakeV4Vault();

    uint256 idForIncrease = _mintPositionToOperator(poolKey);
    IERC721(BASE_PANCAKE_V4_POSM).approve(address(threeTokenVault), idForIncrease);
    threeTokenVault.recoverPosition(
      BASE_PANCAKE_V4_POSM, idForIncrease, address(strategy), address(token0), address(token1)
    );

    hopToken.mint(address(threeTokenVault), 1 ether);

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });
    inputs[2] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(hopToken)), amount: 1 ether });

    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: idForIncrease,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (incParams));
    bytes memory innerData =
      abi.encode(BASE_PANCAKE_V4_POSM, idForIncrease, paramsBytes, uint256(0), new address[](0), new uint256[](0));
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vm.prank(vaultOwner);
    threeTokenVault.execute(actions);
  }

  // ===========================================================================
  // Gap coverage: dispatch guards, slippage floors, revert-safe valuation, and the
  // Pancake-only F19 poolManager pin. Mirrors Integration.SharedVault.V4.t.sol.
  // ===========================================================================

  /// @dev `_mintV4WithAmounts` enforces `liquidity >= minLiquidity` — the swap-and-mint slippage guard.
  function test_swapAndMint_revertsBelowMinLiquidity() public {
    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        minLiquidity: type(uint256).max,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          uint256(0),
          abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)),
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
    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.1 ether });

    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: tokenId,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: type(uint256).max, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          tokenId,
          abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InsufficientOutput.selector
    );
  }

  /// @dev F8: the ADJUST_RANGE round-trip is bounded only by the re-mint's `minLiquidity`.
  function test_execute_adjustRange_revertsBelowMinLiquidity() public {
    IPancakeV4Utils.AdjustRangeParams memory adjustParams = IPancakeV4Utils.AdjustRangeParams({
      collectFeesHookData: "",
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      mintParams: IPancakeV4Utils.MintParams({
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
      BASE_PANCAKE_V4_POSM,
      tokenId,
      abi.encode(
        IPancakeV4Utils.Instructions({
          action: IPancakeV4Utils.UtilActions.ADJUST_RANGE, params: abi.encode(adjustParams)
        })
      )
    );
    _expectRevertExecute(
      bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData),
      ISharedCommon.InsufficientOutput.selector
    );
  }

  /// @dev Pancake-only F19: a caller-supplied `poolKey.poolManager` that is not the POSM's own CL
  ///      pool manager is rejected, so price cannot be read from an attacker-chosen manager. (Uniswap
  ///      V4 has no equivalent because its PoolKey carries no manager field.)
  function test_swapAndMint_rejectsForeignPoolManager() public {
    PoolKey memory foreignKey = PoolKey({
      currency0: poolKey.currency0,
      currency1: poolKey.currency1,
      hooks: IHooks(address(0)),
      poolManager: IPoolManager(address(0xBEEF)),
      fee: LP_FEE,
      parameters: _clParameters(TICK_SPACING)
    });

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: foreignKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });

    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          uint256(0),
          abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev `_execute` rejects any non-zero `ethValue` before touching the POSM.
  function test_execute_revertsWhenEthValueNonZero() public {
    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_PANCAKE_V4_POSM, uint256(0), paramsBytes, uint256(1), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidAmount.selector
    );
  }

  /// @dev `approveTokens.length != approveAmounts.length` is rejected up front with `LengthMismatch`.
  function test_execute_revertsOnApproveArrayLengthMismatch() public {
    address[] memory approveTokens = new address[](1);
    approveTokens[0] = address(token0);
    uint256[] memory approveAmounts = new uint256[](0);

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_PANCAKE_V4_POSM, uint256(0), paramsBytes, uint256(0), approveTokens, approveAmounts)
      ),
      ISharedCommon.LengthMismatch.selector
    );
  }

  /// @dev `swapAndMint` must mint a fresh position, so a non-zero outer tokenId is rejected.
  function test_swapAndMint_revertsWhenTokenIdNonZero() public {
    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (_minimalMintParams()));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_PANCAKE_V4_POSM, tokenId, paramsBytes, uint256(0), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev `swapAndIncrease` must target an existing position, so a zero outer tokenId is rejected.
  function test_swapAndIncrease_revertsWhenTokenIdZero() public {
    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: tokenId,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: new IPancakeV4Utils.InputTokenParams[](0),
      sweepTokens: new Currency[](0),
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(
          BASE_PANCAKE_V4_POSM,
          uint256(0),
          abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (incParams)),
          uint256(0),
          new address[](0),
          new uint256[](0)
        )
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev A params blob whose leading selector matches none of the three supported calls reverts.
  function test_execute_revertsOnUnknownSelector() public {
    bytes memory badParams = abi.encodePacked(bytes4(0xdeadbeef));
    _expectRevertExecute(
      bytes.concat(
        abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE),
        abi.encode(BASE_PANCAKE_V4_POSM, uint256(0), badParams, uint256(0), new address[](0), new uint256[](0))
      ),
      ISharedCommon.InvalidOperation.selector
    );
  }

  /// @dev Valuation must NEVER revert for an unknown/burned tokenId (reached from deposit/withdraw/
  ///      preview). The Pancake path short-circuits a zero `CLPositionInfo` to zeros.
  function test_getPositionAmounts_returnsZeroForUnknownTokenId() public view {
    uint256 bogusId = posm.nextTokenId() + 1000;
    (uint256 amount0, uint256 amount1) = strategy.getPositionAmounts(BASE_PANCAKE_V4_POSM, bogusId);
    assertEq(amount0, 0, "unknown tokenId values token0 to zero");
    assertEq(amount1, 0, "unknown tokenId values token1 to zero");
    (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1) =
      strategy.getPositionAmountsSplit(BASE_PANCAKE_V4_POSM, bogusId);
    assertEq(total0 + total1 + principal0 + principal1, 0, "split valuation also zero, no revert");
  }

  /// @dev `getPositionTokens` resolves the pool currencies to the vault's sorted token pair.
  function test_getPositionTokens_returnsSortedVaultTokens() public view {
    (address t0, address t1) = strategy.getPositionTokens(BASE_PANCAKE_V4_POSM, tokenId);
    assertEq(t0, address(token0), "token0 resolved");
    assertEq(t1, address(token1), "token1 resolved");
  }

  /// @dev Minimal valid mint params (zero floor) reused by dispatch-guard tests whose revert fires
  ///      before the params body is decoded.
  function _minimalMintParams() internal view returns (IPancakeV4Utils.SwapAndMintParams memory) {
    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token0)), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: Currency.wrap(address(token1)), amount: 0.25 ether });
    return IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER, tickUpper: TICK_UPPER, minLiquidity: 0, hookData: "", deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
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
    bytes32 nonce = bytes32(++swapDataNonce);
    bytes32 digest = SharedSwapDataSignature.hash(
      address(vault),
      swapDataSigner,
      address(swapRouter),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      nonce
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SWAP_DATA_SIGNER_PK, digest);
    return abi.encode(rawSwapData, address(vault), deadline, swapDataSigner, nonce, abi.encodePacked(r, s, v));
  }

  function _expectRevertExecute(bytes memory stratData, bytes4 expectedError) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(expectedError);
    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _executePancakeV4(bytes memory stratData) internal {
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(vaultOwner);
    vault.execute(actions);
  }

  function _executePancakeV4Instructions(uint256 id, IPancakeV4Utils.Instructions memory instructions) internal {
    bytes memory innerData = abi.encode(BASE_PANCAKE_V4_POSM, id, abi.encode(instructions));
    _executePancakeV4(bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE_INSTRUCTIONS), innerData));
  }

  function _donatePancakeV4Fees(uint256 amount0, uint256 amount1) internal {
    CLPoolManagerRouter donateRouter =
      new CLPoolManagerRouter(IInfinityVault(address(poolManager.vault())), poolManager);
    token0.approve(address(donateRouter), amount0);
    token1.approve(address(donateRouter), amount1);
    donateRouter.donate(poolKey, amount0, amount1, "");
  }

  function _deployThreeTokenPancakeV4Vault() internal returns (SharedVault threeTokenVault) {
    threeTokenVault = new SharedVault();
    token0.mint(address(threeTokenVault), 10 ether);
    token1.mint(address(threeTokenVault), 10 ether);
    hopToken.mint(address(threeTokenVault), 10 ether);
    address[4] memory tokens = [address(token0), address(token1), address(hopToken), address(0)];
    uint256[4] memory amounts = [uint256(10 ether), uint256(10 ether), uint256(10 ether), uint256(0)];
    threeTokenVault.initialize(
      "SharedVault-PancakeV4-3Token",
      tokens,
      amounts,
      vaultOwner,
      address(this),
      address(configManager),
      address(token0),
      0
    );
  }

  function _deploySortedTokenPair() internal returns (PancakeV4ForkMockERC20 sorted0, PancakeV4ForkMockERC20 sorted1) {
    PancakeV4ForkMockERC20 a = new PancakeV4ForkMockERC20("Token A", "TKNA");
    PancakeV4ForkMockERC20 b = new PancakeV4ForkMockERC20("Token B", "TKNB");
    if (uint160(address(a)) < uint160(address(b))) return (a, b);
    return (b, a);
  }

  function _mintPositionToOperator(PoolKey memory key) internal returns (uint256 mintedTokenId) {
    _approveCurrencyForPosm(Currency.unwrap(key.currency0));
    _approveCurrencyForPosm(Currency.unwrap(key.currency1));

    bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // CL_MINT_POSITION, SETTLE_PAIR
    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(
      key, TICK_LOWER, TICK_UPPER, INITIAL_LIQUIDITY, MAX_TOKEN_IN, MAX_TOKEN_IN, address(this), bytes("")
    );
    params[1] = abi.encode(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));

    mintedTokenId = posm.nextTokenId();
    posm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).ownerOf(mintedTokenId), address(this), "operator owns minted V4 position");
  }

  function _approveCurrencyForPosm(address token) internal {
    IERC20(token).approve(address(permit2), type(uint256).max);
    permit2.approve(token, BASE_PANCAKE_V4_POSM, type(uint160).max, type(uint48).max);
  }

  function _clParameters(int24 tickSpacing) internal pure returns (bytes32) {
    return bytes32(uint256(uint24(tickSpacing)) << 16);
  }
}
