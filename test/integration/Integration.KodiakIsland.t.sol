// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { KodiakIslandStrategy } from "../../contracts/public-vault/strategies/kodiak/KodiakIslandStrategy.sol";
import { IKodiakIslandStrategy } from
  "../../contracts/public-vault/interfaces/strategies/kodiak/IKodiakIslandStrategy.sol";
import { IKodiakIsland } from "../../contracts/public-vault/interfaces/strategies/kodiak/IKodiakIsland.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";
import { PoolOptimalSwapper } from "../../contracts/public-vault/core/PoolOptimalSwapper.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { VaultFactory } from "../../contracts/public-vault/core/VaultFactory.sol";
import { IRewardVault } from "../../contracts/public-vault/interfaces/strategies/kodiak/IRewardVault.sol";

contract IntegrationKodiakIslandTest is Test {
  // Fork configuration
  uint256 constant FORK_BLOCK = 5_249_000;
  string constant FORK_URL = "https://rpc.berachain.com";

  // Contract addresses
  address constant REWARD_VAULT = 0x3Be1bE98eFAcA8c1Eb786Cbf38234c84B5052EeB;
  address constant KODIAK_ISLAND_LP_ADDRESS = 0x564f011D557aAd1cA09BFC956Eb8a17C35d490e0;
  address constant WBERA = 0x6969696969696969696969696969696969696969;
  address constant BGT = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
  address constant OTHER_TOKEN = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
  address constant REWARD_VAULT_FACTORY = 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8;

  // Test contracts
  KodiakIslandStrategy public strategy;
  IKodiakIsland public kodiakIsland;
  IERC20 public wbera;
  IERC20 public otherToken;
  PoolOptimalSwapper public swapper;
  LpFeeTaker public lpFeeTaker;
  ConfigManager public configManager;
  Vault public vault;
  VaultFactory public vaultFactory;

  // Test accounts
  address public owner;
  address public user;
  address public platformFeeRecipient;
  address public gasFeeRecipient;

  // Common configurations
  ICommon.VaultConfig public vaultConfig;

  function setUp() public {
    // Fork the network
    vm.createSelectFork(FORK_URL, FORK_BLOCK);

    // Setup test accounts
    owner = makeAddr("owner");
    user = makeAddr("user");
    platformFeeRecipient = makeAddr("platformFeeRecipient");
    gasFeeRecipient = makeAddr("gasFeeRecipient");
    kodiakIsland = IKodiakIsland(IRewardVault(REWARD_VAULT).stakeToken());

    // Deploy real contracts
    swapper = new PoolOptimalSwapper();

    // Setup LpFeeTaker
    lpFeeTaker = new LpFeeTaker();

    // Deploy strategy with real contracts
    strategy = new KodiakIslandStrategy(address(swapper), REWARD_VAULT_FACTORY, address(lpFeeTaker), BGT, WBERA);
    address[] memory whitelistStrategy = new address[](1);
    whitelistStrategy[0] = address(strategy);

    // Setup ConfigManager
    address[] memory typedTokens = new address[](2);
    typedTokens[0] = WBERA;
    typedTokens[1] = OTHER_TOKEN;

    uint256[] memory typedTokenTypes = new uint256[](2);
    typedTokenTypes[0] = uint256(1);
    typedTokenTypes[1] = uint256(1);

    address[] memory whitelistAutomator = new address[](1);
    whitelistAutomator[0] = user;

    configManager = new ConfigManager();
    configManager.initialize(
      address(this),
      whitelistStrategy,
      new address[](0),
      whitelistAutomator,
      new address[](0),
      typedTokens,
      typedTokenTypes,
      100,
      50,
      50,
      platformFeeRecipient,
      new address[](0),
      new address[](0),
      new bytes[](0)
    );

    // Setup contract instances
    wbera = IERC20(WBERA);
    otherToken = IERC20(OTHER_TOKEN);

    // Setup common configurations
    vaultConfig = ICommon.VaultConfig({
      allowDeposit: true,
      rangeStrategyType: 0,
      tvlStrategyType: 0,
      principalToken: WBERA,
      supportedAddresses: new address[](0)
    });

    // Deploy and setup Vault
    Vault vaultImplementation = new Vault();
    vaultFactory = new VaultFactory();
    vaultFactory.initialize(address(this), WBERA, address(configManager), address(vaultImplementation));

    // Create vault
    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      vaultOwnerFeeBasisPoint: 100,
      name: "Kodiak Island Vault",
      symbol: "KIV",
      principalTokenAmount: 0,
      config: vaultConfig
    });

    // Setup test environment
    vm.startBroadcast(owner);

    address vaultAddress = vaultFactory.createVault(params);
    vault = Vault(payable(vaultAddress));

    vm.deal(owner, 1000 ether);
  }

  function test_InitialSetup() public view {
    // Verify KodiakIsland contract
    assertEq(address(kodiakIsland.token0()), WBERA, "KodiakIsland token0 should be WBERA");
    assertEq(address(kodiakIsland.token1()), OTHER_TOKEN, "KodiakIsland token1 should be OTHER_TOKEN");
    assertTrue(kodiakIsland.manager() != address(0), "KodiakIsland manager should be set");
    assertTrue(
      kodiakIsland.lowerTick() < kodiakIsland.upperTick(), "KodiakIsland lower tick should be less than upper tick"
    );
    assertTrue(kodiakIsland.getPositionID() != bytes32(0), "KodiakIsland position ID should be set");

    // Verify strategy setup
    assertEq(address(strategy.optimalSwapper()), address(swapper), "Strategy optimal swapper should be set correctly");
    assertEq(address(strategy.lpFeeTaker()), address(lpFeeTaker), "Strategy LP fee taker should be set correctly");

    // Verify vault setup
    assertEq(vault.vaultOwner(), owner, "Vault owner should be set correctly");
    assertEq(vault.WETH(), WBERA, "Vault WETH should be set to WBERA");
    (
      bool allowDeposit,
      uint8 rangeStrategyType,
      uint8 tvlStrategyType,
      address principalToken,
      address[] memory supportedAddresses,
      uint16 vaultOwnerFeeBasisPoint
    ) = vault.getVaultConfig();
    assertEq(allowDeposit, vaultConfig.allowDeposit, "Vault deposit allowance should match config");
    assertEq(rangeStrategyType, vaultConfig.rangeStrategyType, "Vault range strategy type should match config");
    assertEq(tvlStrategyType, vaultConfig.tvlStrategyType, "Vault TVL strategy type should match config");
    assertEq(principalToken, vaultConfig.principalToken, "Vault principal token should match config");
    assertEq(
      supportedAddresses.length,
      vaultConfig.supportedAddresses.length,
      "Vault supported addresses length should match config"
    );
    assertEq(vaultOwnerFeeBasisPoint, 100, "Vault owner fee basis point should be set to 100 (1%)");
  }

  function test_Allocate_SwapAndIncreaseLiquidity() public {
    uint256 blockNumber = block.number;
    console2.log("=== Starting test_Allocate_SwapAndIncreaseLiquidity ===");

    // Setup initial deposit
    uint256 depositAmount = 10 ether;
    console2.log("Deposit amount:", depositAmount);

    vault.deposit{ value: depositAmount }(depositAmount, 0);
    console2.log("Deposited WBERA into vault");

    // Setup allocation parameters
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset({
      assetType: AssetLib.AssetType.ERC20,
      token: WBERA,
      strategy: address(0),
      tokenId: 0,
      amount: depositAmount / 2
    });
    console2.log("Created input assets for allocation");

    bytes memory data = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IKodiakIslandStrategy.InstructionType.SwapAndStake),
        params: abi.encode(IKodiakIslandStrategy.SwapAndStakeParams({ kodiakIslandLpAddress: KODIAK_ISLAND_LP_ADDRESS }))
      })
    );
    console2.log("Encoded instruction data for SwapAndStake");

    // Execute allocation
    console2.log("Executing allocation...");
    vault.allocate(inputAssets, strategy, 0, data);
    console2.log("Allocation completed");

    // Verify results
    AssetLib.Asset[] memory inventory = vault.getInventory();
    console2.log("Vault inventory length:", inventory.length);
    console2.log("Token 0:", inventory[0].token);
    console2.log("Token 1:", inventory[1].token);
    console2.log("Token 2:", inventory[2].token);
    console2.log("Strategy address:", inventory[2].strategy);

    assertEq(inventory.length, 3, "Vault should have 3 assets after allocation");
    assertEq(inventory[0].token, WBERA, "First asset should be WBERA");
    assertEq(inventory[1].token, OTHER_TOKEN, "Second asset should be OTHER_TOKEN");
    assertEq(inventory[2].token, REWARD_VAULT, "Third asset should be RewardVault token");
    assertEq(inventory[2].strategy, address(strategy), "LP token should be managed by the strategy");

    console2.log("Initial allocation completed");

    uint256 accumulatedBgtReward = 45_824_107_162_258_373; // After 10 days
    uint256 vaultTotalValueBefore = vault.getTotalValue();
    assertApproxEqRel(vaultTotalValueBefore, 10 ether, 0.01e18, "Vault value should be 10 ether");
    vm.roll(blockNumber + 5000);
    vm.warp(block.timestamp + 10 * 86_400);
    uint256 vaultTotalValueAfter = vault.getTotalValue();
    assertEq(vaultTotalValueAfter - vaultTotalValueBefore, accumulatedBgtReward, "Vault value should increase");

    // Now decrease liquidity
    inputAssets[0] = inventory[2];
    console2.log("Created input assets for decrease liquidity");

    data = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IKodiakIslandStrategy.InstructionType.WithdrawAndSwap),
        params: abi.encode(IKodiakIslandStrategy.WithdrawAndSwapParams({ minPrincipalAmount: 0 }))
      })
    );
    console2.log("Encoded instruction data for DecreaseLiquidityAndSwap");

    uint256 ownerBalanceBefore = wbera.balanceOf(owner);
    uint256 platformBalanceBefore = wbera.balanceOf(platformFeeRecipient);
    uint64 gasFeeX64 = 184_467_440_737_095_520; // ~1% in Q64

    // Execute allocation
    console2.log("Executing decrease liquidity allocation...");
    vault.allocate(inputAssets, strategy, gasFeeX64, data);
    console2.log("Decrease liquidity allocation completed");

    uint256 ownerBalanceAfter = wbera.balanceOf(owner);
    uint256 platformBalanceAfter = wbera.balanceOf(platformFeeRecipient);
    assertEq(ownerBalanceAfter - ownerBalanceBefore, accumulatedBgtReward / 100, "Owner should receive 1% of rewards");
    assertEq(
      platformBalanceAfter - platformBalanceBefore,
      accumulatedBgtReward / 200 + accumulatedBgtReward / 100,
      "Platform fee recipient should receive 0.5% as platform fee and 1% as gas fee"
    );

    // Verify results
    inventory = vault.getInventory();
    console2.log("Final vault inventory length:", inventory.length);
    console2.log("Token 0:", inventory[0].token);
    console2.log("Amount 0:", inventory[0].amount);
    console2.log("Token 1:", inventory[1].token);
    console2.log("Amount 1:", inventory[1].amount);

    assertApproxEqRel(
      vault.getTotalValue(), 10 ether + (accumulatedBgtReward * 975) / 1000, 0.01e18, "Vault value should be 10 ether"
    );

    assertEq(inventory.length, 2, "Vault should have 2 assets after decreasing liquidity");
    assertEq(inventory[0].token, WBERA, "First asset should be WBERA");
    assertEq(inventory[1].token, OTHER_TOKEN, "Second asset should be OTHER_TOKEN");
    console2.log("All assertions passed");
  }
}
