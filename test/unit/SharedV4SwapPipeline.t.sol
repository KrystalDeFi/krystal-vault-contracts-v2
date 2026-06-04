// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedV4Utils } from "../../contracts/shared-vault/interfaces/ISharedV4Utils.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";
import { SharedV4SwapPipeline } from "../../contracts/shared-vault/libraries/SharedV4SwapPipeline.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

contract SharedV4SwapPipelineTestToken is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract SharedV4SwapPipelineConfigManager {
  address public router;
  address public signer;

  constructor(address _router, address _signer) {
    router = _router;
    signer = _signer;
  }

  function isWhitelistedSwapRouter(address account) external view returns (bool) {
    return account == router;
  }

  function isWhitelistedSigner(address account) external view returns (bool) {
    return account == signer;
  }
}

contract SharedV4SwapPipelineRouter {
  function swapAll(address tokenIn, address tokenOut, uint256 amountOut) external {
    uint256 amountIn = ERC20(tokenIn).allowance(msg.sender, address(this));
    ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    ERC20(tokenOut).transfer(msg.sender, amountOut);
  }
}

contract SharedV4SwapPipelineHarness {
  address public immutable weth;
  ISharedConfigManager public immutable configManager;

  constructor(address _configManager, address _weth) {
    configManager = ISharedConfigManager(_configManager);
    weth = _weth;
  }

  function execute(
    address swapRouter,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    ISharedV4Utils.SwapParams[] memory swapParams
  ) external returns (uint256 total0, uint256 total1) {
    return SharedV4SwapPipeline.execute(swapRouter, token0, token1, amount0, amount1, swapParams);
  }
}

contract SharedV4SwapPipelineTest is Test {
  uint256 internal constant SIGNER_PK = 0xA11CE;

  SharedV4SwapPipelineTestToken internal token0;
  SharedV4SwapPipelineTestToken internal token1;
  SharedV4SwapPipelineRouter internal router;
  SharedV4SwapPipelineHarness internal harness;
  address internal signer;
  uint256 internal nonce;

  function setUp() public {
    signer = vm.addr(SIGNER_PK);
    token0 = new SharedV4SwapPipelineTestToken("Token 0", "TK0");
    token1 = new SharedV4SwapPipelineTestToken("Token 1", "TK1");
    router = new SharedV4SwapPipelineRouter();
    SharedV4SwapPipelineConfigManager configManager = new SharedV4SwapPipelineConfigManager(address(router), signer);
    harness = new SharedV4SwapPipelineHarness(address(configManager), address(token0));
  }

  function test_execute_acceptsSignatureBoundToDeclaredZeroAmountSentinel() public {
    uint256 runtimeAmountIn = 10 ether;
    uint256 amountOut = 5 ether;
    bytes memory rawSwapData =
      abi.encodeCall(SharedV4SwapPipelineRouter.swapAll, (address(token0), address(token1), amountOut));

    token0.mint(address(harness), runtimeAmountIn);
    token1.mint(address(router), amountOut);

    ISharedV4Utils.SwapParams[] memory swaps = new ISharedV4Utils.SwapParams[](1);
    swaps[0] = ISharedV4Utils.SwapParams({
      tokenIn: Currency.wrap(address(token0)),
      amountIn: 0,
      tokenOut: Currency.wrap(address(token1)),
      amountOutMin: amountOut,
      swapData: _signedSwapData(address(token0), address(token1), 0, amountOut, rawSwapData)
    });

    (uint256 total0, uint256 total1) =
      harness.execute(address(router), address(token0), address(token1), runtimeAmountIn, 0, swaps);

    assertEq(total0, 0, "swap-all consumed runtime token0 balance");
    assertEq(total1, amountOut, "swap output credited to token1 total");
    assertEq(token0.balanceOf(address(harness)), 0, "harness token0 spent");
    assertEq(token1.balanceOf(address(harness)), amountOut, "harness received token1");
  }

  function _signedSwapData(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 swapNonce = bytes32(++nonce);
    bytes32 digest = SharedSwapDataSignature.hash(
      address(harness),
      signer,
      address(router),
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      swapNonce
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
    return abi.encode(rawSwapData, address(harness), deadline, signer, swapNonce, abi.encodePacked(r, s, v));
  }
}
