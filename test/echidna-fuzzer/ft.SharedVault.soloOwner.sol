// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Foundry companion for Fuzzer.SharedVault.soloOwner — use to debug failing sequences locally.

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

contract FtSharedVaultSoloOwner is TestCommon {
  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  address public vault;

  function setUp() public {
    uint256 fork = vm.createFork(vm.envString("RPC_URL"), SV_BLOCK_NUMBER);
    vm.selectFork(fork);

    owner = new SharedVaultPlayer();
    player1 = new SharedVaultPlayer();
    player2 = new SharedVaultPlayer();

    setErc20Balance(SV_WETH, address(owner), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player1), SV_INITIAL_WETH);
    setErc20Balance(SV_WETH, address(player2), SV_INITIAL_WETH);
    setErc20Balance(SV_USDC, address(owner), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player1), SV_INITIAL_USDC);
    setErc20Balance(SV_USDC, address(player2), SV_INITIAL_USDC);

    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;
    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner),
      new address[](0),
      new address[](0),
      SV_FEE_RECIPIENT,
      0,
      nfpms,
      new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "SoloOwner", vaultTokens, initAmounts, 0);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    player2.callDeposit(vault, pAmounts, 0);
  }

  function test_printState() public view {
    console.log("vault:", vault);
    console.log("owner shares:", owner.sharesBalance(vault));
    console.log("player1 shares:", player1.sharesBalance(vault));
    console.log("player2 shares:", player2.sharesBalance(vault));
    console.log("vault total supply:", IERC20(vault).totalSupply());
    uint256[4] memory totals = SharedVault(payable(vault)).getTotalBalances();
    console.log("vault WETH total:", totals[0]);
    console.log("vault USDC total:", totals[1]);
  }

  function test_ownerWithdrawAll() public {
    uint256 ownerSharesBefore = owner.sharesBalance(vault);
    owner.callWithdraw(vault, ownerSharesBefore, false);
    assertEq(owner.sharesBalance(vault), 0);
    assertLe(IERC20(SV_WETH).balanceOf(address(owner)), SV_INITIAL_WETH + 1e9);
  }
}
