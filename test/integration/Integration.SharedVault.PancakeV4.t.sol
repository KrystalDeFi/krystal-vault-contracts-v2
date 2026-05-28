// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestCommon } from "../TestCommon.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import {
  IPancakeV4CLPoolManager,
  IPancakeV4PositionManager
} from "../../contracts/shared-vault/interfaces/IPancakeV4PositionManager.sol";
import {
  ISharedPancakeV4Utils as IPancakeV4Utils,
  PancakeV4PoolKey
} from "../../contracts/shared-vault/interfaces/ISharedPancakeV4Utils.sol";
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

  IPancakeV4PositionManager internal posm;
  IPancakeV4CLPoolManager internal poolManager;
  IAllowanceTransfer internal permit2;
  PancakeV4ForkMockERC20 internal token0;
  PancakeV4ForkMockERC20 internal token1;
  PancakeV4ForkMockERC20 internal hopToken;
  PancakeV4PoolKey internal poolKey;
  SharedConfigManager internal configManager;
  SharedVault internal vault;
  SharedPancakeV4Strategy internal strategy;
  PancakeV4RecordingSwapRouter internal swapRouter;
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

    posm = IPancakeV4PositionManager(BASE_PANCAKE_V4_POSM);
    poolManager = IPancakeV4CLPoolManager(posm.clPoolManager());
    permit2 = IAllowanceTransfer(posm.permit2());

    (token0, token1) = _deploySortedTokenPair();
    hopToken = new PancakeV4ForkMockERC20("Hop", "HOP");
    poolKey = PancakeV4PoolKey({
      currency0: address(token0),
      currency1: address(token1),
      hooks: address(0),
      poolManager: address(poolManager),
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
    configManager = new SharedConfigManager();
    configManager.initialize(address(this), targets, new address[](0), feeRecipient, 0, nfpms, new address[](0));

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

    (uint160 permitAmount0,,) = permit2.allowance(address(vault), address(token0), BASE_PANCAKE_V4_POSM);
    (uint160 permitAmount1,,) = permit2.allowance(address(vault), address(token1), BASE_PANCAKE_V4_POSM);
    assertEq(permitAmount0, 0, "token0 Permit2 POSM allowance cleared");
    assertEq(permitAmount1, 0, "token1 Permit2 POSM allowance cleared");
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
        liquidity: 0.5 ether, deadline: block.timestamp, amount0Min: 0, amount1Min: 0, hookData: ""
      }),
      swapParams: swaps,
      swapDestToken: address(token1),
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
    assertEq(keccak256(swapRouter.lastData()), keccak256(swaps[1].swapData), "router receives final hop payload");
    assertGt(token1.balanceOf(address(vault)), token1Before, "vault receives final hop output");
    assertEq(token0.allowance(address(vault), address(swapRouter)), 0, "token0 router approval cleared");
    assertEq(hopToken.allowance(address(vault), address(swapRouter)), 0, "hop router approval cleared");
    assertEq(token1.allowance(address(vault), address(swapRouter)), 0, "token1 router approval cleared");
    assertEq(IERC721(BASE_PANCAKE_V4_POSM).getApproved(tokenId), address(0), "NFT approval cleared");
  }

  function _deploySortedTokenPair() internal returns (PancakeV4ForkMockERC20 sorted0, PancakeV4ForkMockERC20 sorted1) {
    PancakeV4ForkMockERC20 a = new PancakeV4ForkMockERC20("Token A", "TKNA");
    PancakeV4ForkMockERC20 b = new PancakeV4ForkMockERC20("Token B", "TKNB");
    if (uint160(address(a)) < uint160(address(b))) return (a, b);
    return (b, a);
  }

  function _mintPositionToOperator(PancakeV4PoolKey memory key) internal returns (uint256 mintedTokenId) {
    _approveCurrencyForPosm(key.currency0);
    _approveCurrencyForPosm(key.currency1);

    bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // CL_MINT_POSITION, SETTLE_PAIR
    bytes[] memory params = new bytes[](2);
    params[0] =
      abi.encode(key, TICK_LOWER, TICK_UPPER, INITIAL_LIQUIDITY, MAX_TOKEN_IN, MAX_TOKEN_IN, address(this), bytes(""));
    params[1] = abi.encode(key.currency0, key.currency1);

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
