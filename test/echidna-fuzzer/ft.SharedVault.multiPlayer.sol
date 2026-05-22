// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract FtSharedVaultMultiPlayer is TestCommon {
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedVaultPlayer public player3;
  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  address public vault;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), SV_BLOCK_NUMBER);
    vm.selectFork(fork);

    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();
    player3 = new SharedVaultPlayer();

    setErc20Balance(SV_WETH, address(player1), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player2), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player3), SV_INITIAL_WETH);
    setErc20Balance(SV_USDC, address(player1), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player2), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player3), SV_INITIAL_USDC);

    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(player1),
      new address[](0),
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(player1), address(configManager), address(vaultImpl), SV_WETH);

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = player1.callCreateVault(address(vaultFactory), "MultiPlayer", vaultTokens, initAmounts, 0);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player2.callDeposit(vault, pAmounts, 0);
    player3.callDeposit(vault, pAmounts, 0);
  }

  function test_shareSupplyConsistency() public view {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sum = player1.sharesBalance(vault) + player2.sharesBalance(vault) + player3.sharesBalance(vault);
    assertEq(supply, sum);
  }

  function test_allPlayersWithdraw() public {
    player1.callWithdraw(vault, player1.sharesBalance(vault), false);
    player2.callWithdraw(vault, player2.sharesBalance(vault), false);
    player3.callWithdraw(vault, player3.sharesBalance(vault), false);
    assertEq(IERC20(vault).totalSupply(), 0);
  }
}
