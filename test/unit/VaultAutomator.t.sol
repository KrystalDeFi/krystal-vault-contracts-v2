// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { TestCommon, USER, WETH, DAI, USDC, NFPM } from "../TestCommon.t.sol";
import { VaultAutomatorLpStrategy } from "../helpers/VaultAutomatorLpStrategy.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AssetLib } from "../../contracts/libraries/AssetLib.sol";
import { StructHash as LpUniV3StructHash } from "../../contracts/libraries/strategies/LpUniV3StructHash.sol";

import { ICommon } from "../../contracts/interfaces/ICommon.sol";
import { PoolOptimalSwapper } from "../../contracts/core/PoolOptimalSwapper.sol";
import { ConfigManager } from "../../contracts/core/ConfigManager.sol";
import { LpStrategy } from "../../contracts/strategies/lpUniV3/LpStrategy.sol";
import { LpValidator } from "../../contracts/strategies/lpUniV3/LpValidator.sol";
import { ILpStrategy } from "../../contracts/interfaces/strategies/ILpStrategy.sol";
import { ILpValidator } from "../../contracts/interfaces/strategies/ILpValidator.sol";
import { VaultFactory } from "../../contracts/core/VaultFactory.sol";
import { IVaultFactory } from "../../contracts/interfaces/core/IVaultFactory.sol";
import { IVault } from "../../contracts/interfaces/core/IVault.sol";
import { Vault } from "../../contracts/core/Vault.sol";
import { VaultAutomator } from "../../contracts/strategies/lpUniV3/VaultAutomator.sol";
import { INonfungiblePositionManager as INFPM } from
  "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract VaultAutomatorTest is TestCommon {
  LpUniV3StructHash.Order emptyUserConfig;

  ConfigManager public configManager;
  ILpStrategy public lpStrategy;
  Vault public vault;
  VaultAutomatorLpStrategy public vaultAutomatorLpStrategy;
  VaultFactory public vaultFactory;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), 27_448_360);
    vm.selectFork(fork);

    vm.startBroadcast(USER);

    setErc20Balance(WETH, USER, 100 ether);
    vm.deal(USER, 100 ether);

    PoolOptimalSwapper swapper = new PoolOptimalSwapper();
    vaultAutomatorLpStrategy = new VaultAutomatorLpStrategy(USER);

    address[] memory typedTokens = new address[](2);
    typedTokens[0] = DAI;
    typedTokens[1] = USDC;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(ILpValidator.TokenType.Stable);
    typedTokenTypes[1] = uint256(ILpValidator.TokenType.Stable);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = address(vaultAutomatorLpStrategy);

    configManager = new ConfigManager(USER, whitelistAutomator, typedTokens, typedTokenTypes);
    LpValidator validator = new LpValidator(address(configManager));
    lpStrategy = new LpStrategy(address(swapper), address(validator));

    address[] memory whitelistStrategies = new address[](1);
    whitelistStrategies[0] = address(lpStrategy);
    configManager.whitelistStrategy(whitelistStrategies, true);

    vault = new Vault();

    vaultFactory = new VaultFactory(USER, WETH, address(configManager), address(vault));
  }

  function test_executeAllocateLpStrategy() public {
    console.log("==== createVault ====");

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      name: "Test Vault",
      symbol: "TV",
      principalTokenAmount: 1 ether,
      config: ICommon.VaultConfig({
        allowDeposit: false,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: WETH,
        supportedAddresses: new address[](0)
      })
    });

    (address vaultOwner, uint256 privateKey) = makeAddrAndKey("vaultOwner");
    setErc20Balance(WETH, vaultOwner, 100 ether);
    vm.deal(vaultOwner, 100 ether);
    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    IERC20(WETH).approve(address(vaultFactory), 1 ether);
    address vaultAddress = vaultFactory.createVault(params);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    assertEq(IERC20(WETH).balanceOf(vaultAddress), 1 ether);
    assertEq(IERC20(vaultAddress).balanceOf(vaultOwner), 1 ether * vault.SHARES_PRECISION());

    AssetLib.Asset[] memory assets = new AssetLib.Asset[](1);
    assets[0] = AssetLib.Asset(AssetLib.AssetType.ERC20, address(0), WETH, 0, 0.8 ether);

    ILpStrategy.SwapAndMintPositionParams memory strategyParams = ILpStrategy.SwapAndMintPositionParams({
      nfpm: INFPM(NFPM),
      token0: WETH,
      token1: USDC,
      fee: 500,
      tickLower: -887_220,
      tickUpper: 887_200,
      amount0Min: 0,
      amount1Min: 0,
      swapData: ""
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(ILpStrategy.InstructionType.SwapAndMintPosition),
      params: abi.encode(strategyParams)
    });

    vm.stopBroadcast();
    vm.startBroadcast(vaultOwner);
    bytes memory signature = _signLpStrategyOrder(emptyUserConfig, privateKey);
    vm.stopBroadcast();
    vm.startBroadcast(USER);

    vm.expectRevert(ICommon.InvalidInstructionType.selector);
    vaultAutomatorLpStrategy.executeAllocate(
      IVault(vaultAddress), assets, lpStrategy, 0, abi.encode(instruction), abi.encode(emptyUserConfig), signature
    );

    // assertEq(IERC20(vaultAddress).balanceOf(vaultOwner), 1 ether * vault.SHARES_PRECISION());

    // AssetLib.Asset[] memory vaultAssets = IVault(vaultAddress).getInventory();

    // assertEq(vaultAssets.length, 3);
    // assertEq(vaultAssets[2].strategy, address(lpStrategy));
    // assertEq(vaultAssets[2].token, NFPM);
  }

  function _signLpStrategyOrder(LpUniV3StructHash.Order memory order, uint256 privateKey)
    internal
    view
    returns (bytes memory signature)
  {
    bytes32 digest = vaultAutomatorLpStrategy.hashTypedDataV4(LpUniV3StructHash._hash(order));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    signature = abi.encodePacked(r, s, v);
  }
}
