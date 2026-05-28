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

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedV4Strategy, IV4Utils } from "../../contracts/shared-vault/strategies/SharedV4Strategy.sol";

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

  receive() external payable { }

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), BASE_FORK_BLOCK);
    vm.selectFork(fork);

    vaultOwner = makeAddr("vaultOwner");
    depositor = makeAddr("depositor");
    feeRecipient = makeAddr("feeRecipient");

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
    configManager = new SharedConfigManager();
    configManager.initialize(address(this), targets, new address[](0), feeRecipient, 0, nfpms, new address[](0));

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
    uint256 shares = vault.deposit(amounts, 1);
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

    IV4Utils.SwapParams[] memory swaps = new IV4Utils.SwapParams[](2);
    swaps[0] = IV4Utils.SwapParams({
      tokenIn: address(token0),
      amountIn: 0.01 ether,
      tokenOut: address(hopToken),
      amountOutMin: 1,
      swapData: abi.encodeCall(RecordingSwapRouter.swap, (address(token0), address(hopToken), 0.01 ether))
    });
    swaps[1] = IV4Utils.SwapParams({
      tokenIn: address(hopToken),
      amountIn: 0,
      tokenOut: address(token1),
      amountOutMin: 1,
      swapData: abi.encodeCall(RecordingSwapRouter.swap, (address(hopToken), address(token1), 0.01 ether))
    });

    IV4Utils.DecreaseAndSwapParams memory decParams = IV4Utils.DecreaseAndSwapParams({
      decreaseParams: IV4Utils.DecreaseLiquidityParams({
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: address(token1),
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
    assertEq(keccak256(swapRouter.lastData()), keccak256(swaps[1].swapData), "router receives final hop payload");
    assertGt(token1.balanceOf(address(vault)), token1Before, "vault receives final hop output");
    assertEq(token0.allowance(address(vault), address(swapRouter)), 0, "token0 router approval cleared");
    assertEq(hopToken.allowance(address(vault), address(swapRouter)), 0, "hop router approval cleared");
    assertEq(token1.allowance(address(vault), address(swapRouter)), 0, "token1 router approval cleared");
    assertEq(IERC721(BASE_V4_POSM).getApproved(tokenId), address(0), "NFT approval cleared");
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

    params[0] =
      abi.encode(key, TICK_LOWER, TICK_UPPER, INITIAL_LIQUIDITY, MAX_TOKEN_IN, MAX_TOKEN_IN, address(this), bytes(""));
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
