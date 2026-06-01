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
import { ICLPoolManager } from "infinity-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { ICLPositionManager } from "infinity-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import { IPositionManagerPermit2 } from "infinity-periphery/src/interfaces/IPositionManagerPermit2.sol";
import { ISharedPancakeV4Utils as IPancakeV4Utils } from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
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

  receive() external payable {}

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    vm.selectFork(fork);

    vaultOwner = makeAddr("vaultOwner");
    depositor = makeAddr("depositor");
    feeRecipient = makeAddr("feeRecipient");

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
    configManager.initialize(address(this), targets, new address[](0), feeRecipient, 0, nfpms, swapRouters);

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
    uint256 shares = vault.deposit(amounts, 1);
    vm.stopPrank();

    assertGt(shares, 0, "deposit mints shares");
    assertGt(posm.getPositionLiquidity(tokenId), liquidityBefore, "Pancake V4 liquidity increases");
    assertEq(token0.allowance(address(vault), address(permit2)), 0, "token0 ERC20 Permit2 approval cleared");
    assertEq(token1.allowance(address(vault), address(permit2)), 0, "token1 ERC20 Permit2 approval cleared");

    (uint160 permitAmount0, , ) = permit2.allowance(address(vault), address(token0), BASE_PANCAKE_V4_POSM);
    (uint160 permitAmount1, , ) = permit2.allowance(address(vault), address(token1), BASE_PANCAKE_V4_POSM);
    assertEq(permitAmount0, 0, "token0 Permit2 POSM allowance cleared");
    assertEq(permitAmount1, 0, "token1 Permit2 POSM allowance cleared");
  }

  function test_swapAndMint_createsTrackedPositionWithRealPancakeV4PositionManager() public {
    uint256 countBefore = vault.getPositionCount();
    uint256 nextIdBefore = posm.nextTokenId();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: address(token0), amount: 0.25 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: address(token1), amount: 0.25 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
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

  function test_swapAndIncrease_addsLiquidityToTrackedPositionWithRealPancakeV4PositionManager() public {
    uint128 liquidityBefore = posm.getPositionLiquidity(tokenId);
    uint256 countBefore = vault.getPositionCount();

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](2);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: address(token0), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: address(token1), amount: 0.1 ether });

    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: tokenId,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
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
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
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
        action: IPancakeV4Utils.UtilActions.ADJUST_RANGE,
        params: abi.encode(adjustParams)
      })
    );

    assertEq(vault.getPositionCount(), 1, "range adjust replaces one tracked position");
    (, , uint256 trackedTokenId, , ) = vault.getPosition(0);
    assertEq(trackedTokenId, nextIdBefore, "new Pancake V4 tokenId tracked");
    assertGt(posm.getPositionLiquidity(nextIdBefore), 0, "replacement Pancake V4 position has liquidity");
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

    IPancakeV4Utils.SwapParams[] memory swaps = new IPancakeV4Utils.SwapParams[](2);
    swaps[0] = IPancakeV4Utils.SwapParams({
      tokenIn: address(token0),
      amountIn: 0.01 ether,
      tokenOut: address(hopToken),
      amountOutMin: 1,
      swapData: abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether))
    });
    swaps[1] = IPancakeV4Utils.SwapParams({
      tokenIn: address(hopToken),
      amountIn: 0,
      tokenOut: address(token1),
      amountOutMin: 1,
      swapData: abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.01 ether))
    });

    IPancakeV4Utils.DecreaseAndSwapParams memory decParams = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether,
        deadline: block.timestamp,
        amount0Min: 0,
        amount1Min: 0,
        hookData: ""
      }),
      swapParams: swaps,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory instructions = IPancakeV4Utils.Instructions({
      action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP,
      params: abi.encode(decParams)
    });
    bytes memory params = abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, tokenId, instructions));
    bytes memory innerData = abi.encode(
      BASE_PANCAKE_V4_POSM,
      tokenId,
      params,
      uint256(0),
      new address[](0),
      new uint256[](0)
    );
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.prank(vaultOwner);
    vault.execute(actions);

    assertEq(swapRouter.callCount(), 2, "native strategy executes both swap hops");
    assertEq(keccak256(swapRouter.lastData()), keccak256(swaps[1].swapData), "router receives final hop payload");
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
    IPancakeV4Utils.SwapParams[] memory swaps = new IPancakeV4Utils.SwapParams[](2);
    swaps[0] = IPancakeV4Utils.SwapParams({
      tokenIn: address(token0),
      amountIn: 0.01 ether,
      tokenOut: address(hopToken),
      amountOutMin: 1,
      swapData: abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether))
    });
    swaps[1] = IPancakeV4Utils.SwapParams({
      tokenIn: address(hopToken),
      amountIn: 0.005 ether, // hop 1 produced 0.01 ether; consuming only half leaves leftover
      tokenOut: address(token1),
      amountOutMin: 1,
      swapData: abi.encodeCall(PancakeV4RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.005 ether))
    });

    IPancakeV4Utils.DecreaseAndSwapParams memory decParams = IPancakeV4Utils.DecreaseAndSwapParams({
      decreaseParams: IPancakeV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether,
        deadline: block.timestamp,
        amount0Min: 0,
        amount1Min: 0,
        hookData: ""
      }),
      swapParams: swaps,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: 0
    });
    IPancakeV4Utils.Instructions memory instructions = IPancakeV4Utils.Instructions({
      action: IPancakeV4Utils.UtilActions.DECREASE_AND_SWAP,
      params: abi.encode(decParams)
    });
    bytes memory params = abi.encodeCall(IPancakeV4Utils.execute, (BASE_PANCAKE_V4_POSM, tokenId, instructions));
    bytes memory innerData = abi.encode(
      BASE_PANCAKE_V4_POSM,
      tokenId,
      params,
      uint256(0),
      new address[](0),
      new uint256[](0)
    );
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
  // have `_takeInputGasFeesAndGetPoolAmounts` send `amount * gasFeeX64 / Q64` of that token to
  // `msg.sender` before the per-entry currency check — the remainder then dropped silently from
  // the LP accounting. After the fix, every positive-amount input must match `currency0` or
  // `currency1`, so the path reverts with `InvalidPoolTokens()` before any fee transfer.
  // ===========================================================================

  function test_swapAndMint_rejectsNonPoolInputToken_preventsGasFeeSiphon() public {
    SharedVault threeTokenVault = _deployThreeTokenPancakeV4Vault();
    hopToken.mint(address(threeTokenVault), 1 ether);

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: address(token0), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: address(token1), amount: 0.1 ether });
    inputs[2] = IPancakeV4Utils.InputTokenParams({ token: address(hopToken), amount: 1 ether });

    IPancakeV4Utils.SwapAndMintParams memory mintParams = IPancakeV4Utils.SwapAndMintParams({
      posm: BASE_PANCAKE_V4_POSM,
      poolKey: poolKey,
      mintParams: IPancakeV4Utils.MintParams({
        tickLower: TICK_LOWER,
        tickUpper: TICK_UPPER,
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndMint, (mintParams));
    bytes memory innerData = abi.encode(
      BASE_PANCAKE_V4_POSM,
      uint256(0),
      paramsBytes,
      uint256(0),
      new address[](0),
      new uint256[](0)
    );
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
      BASE_PANCAKE_V4_POSM,
      idForIncrease,
      address(strategy),
      address(token0),
      address(token1)
    );

    hopToken.mint(address(threeTokenVault), 1 ether);

    IPancakeV4Utils.InputTokenParams[] memory inputs = new IPancakeV4Utils.InputTokenParams[](3);
    inputs[0] = IPancakeV4Utils.InputTokenParams({ token: address(token0), amount: 0.1 ether });
    inputs[1] = IPancakeV4Utils.InputTokenParams({ token: address(token1), amount: 0.1 ether });
    inputs[2] = IPancakeV4Utils.InputTokenParams({ token: address(hopToken), amount: 1 ether });

    IPancakeV4Utils.SwapAndIncreaseParams memory incParams = IPancakeV4Utils.SwapAndIncreaseParams({
      posm: BASE_PANCAKE_V4_POSM,
      tokenId: idForIncrease,
      increaseParams: IPancakeV4Utils.IncreaseLiquidityParams({
        minLiquidity: 0,
        hookData: "",
        deadline: block.timestamp + 300
      }),
      swapParams: new IPancakeV4Utils.SwapParams[](0),
      inputTokens: inputs,
      protocolFeeX64: 0,
      performanceFeeX64: 0,
      gasFeeX64: uint64(uint256(0x10000000000000000) / 2)
    });

    bytes memory paramsBytes = abi.encodeCall(IPancakeV4Utils.swapAndIncrease, (incParams));
    bytes memory innerData = abi.encode(
      BASE_PANCAKE_V4_POSM,
      idForIncrease,
      paramsBytes,
      uint256(0),
      new address[](0),
      new uint256[](0)
    );
    bytes memory stratData = bytes.concat(abi.encode(SharedPancakeV4Strategy.OperationType.EXECUTE), innerData);

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action(address(strategy), stratData, ISharedCommon.CallType.DELEGATECALL);

    vm.expectRevert(ISharedStrategy.InvalidPoolTokens.selector);
    vm.prank(vaultOwner);
    threeTokenVault.execute(actions);
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
      key,
      TICK_LOWER,
      TICK_UPPER,
      INITIAL_LIQUIDITY,
      MAX_TOKEN_IN,
      MAX_TOKEN_IN,
      address(this),
      bytes("")
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
