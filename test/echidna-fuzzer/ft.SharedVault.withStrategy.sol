// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultFactory } from "../../contracts/shared-vault/core/SharedVaultFactory.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { SharedV3Strategy } from "../../contracts/shared-vault/strategies/SharedV3Strategy.sol";
import { LpFeeTaker } from "../../contracts/public-vault/strategies/lpUniV3/LpFeeTaker.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { IV3Utils } from "../../contracts/private-vault/interfaces/strategies/lpv3/IV3Utils.sol";
import { TestCommon } from "../TestCommon.t.sol";
import "./SharedVaultConfig.sol";
import "./SharedVaultPlayer.sol";

contract FtSharedVaultWithStrategy is TestCommon {
  SharedVaultPlayer public owner;
  SharedVaultPlayer public player1;
  SharedVaultPlayer public player2;
  SharedConfigManager public configManager;
  SharedVaultFactory public vaultFactory;
  SharedV3Strategy public v3Strategy;
  address public vault;
  uint16 public constant FEE_BPS = 500;

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

    LpFeeTaker lpFeeTaker = new LpFeeTaker();
    v3Strategy = new SharedV3Strategy(SV_V3UTILS, address(lpFeeTaker));

    address[] memory targets = new address[](1);
    targets[0] = address(v3Strategy);
    address[] memory nfpms = new address[](1);
    nfpms[0] = SV_NFPM;

    configManager = new SharedConfigManager();
    configManager.initialize(
      address(owner), targets, new address[](0), SV_FEE_RECIPIENT, 0, nfpms, new address[](0)
    );

    SharedVault vaultImpl = new SharedVault();
    vaultFactory = new SharedVaultFactory();
    vaultFactory.initialize(address(owner), address(configManager), address(vaultImpl), SV_WETH);

    address[4] memory vaultTokens = [SV_WETH, SV_USDC, address(0), address(0)];
    uint256[4] memory initAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    vault = owner.callCreateVault(address(vaultFactory), "WithStrategy", vaultTokens, initAmounts, FEE_BPS);

    uint256[4] memory pAmounts = [uint256(1 ether), uint256(3_000e6), 0, 0];
    player1.callDeposit(vault, pAmounts, 0);
    player2.callDeposit(vault, pAmounts, 0);
  }

  function test_feeBpsImmutable() public view {
    assertEq(SharedVault(payable(vault)).vaultOwnerFeeBasisPoint(), FEE_BPS);
  }

  function test_shareSupplyConsistency() public view {
    uint256 supply = IERC20(vault).totalSupply();
    uint256 sum = owner.sharesBalance(vault) + player1.sharesBalance(vault) + player2.sharesBalance(vault);
    assertEq(supply, sum);
  }

  function test_openLpThenWithdrawAll() public {
    // Open LP position with half the vault's idle balance
    uint256[4] memory idle = SharedVault(payable(vault)).getIdleBalances();
    uint256 amt0 = idle[0] / 2;
    uint256 amt1 = idle[1] / 2;

    address[] memory approveTokens = new address[](2);
    approveTokens[0] = SV_WETH;
    approveTokens[1] = SV_USDC;
    uint256[] memory approveAmounts = new uint256[](2);
    approveAmounts[0] = amt0;
    approveAmounts[1] = amt1;

    IV3Utils.SwapAndMintParams memory params = IV3Utils.SwapAndMintParams({
      protocol: 0,
      nfpm: SV_NFPM,
      token0: SV_WETH,
      token1: SV_USDC,
      fee: SV_POOL_FEE,
      tickSpacing: 10,
      tickLower: SV_TICK_LOWER,
      tickUpper: SV_TICK_UPPER,
      protocolFeeX64: 0,
      gasFeeX64: 0,
      amount0: amt0,
      amount1: amt1,
      amount2: 0,
      recipient: address(0),
      deadline: block.timestamp + 300,
      swapSourceToken: address(0),
      amountIn0: 0,
      amountOut0Min: 0,
      swapData0: "",
      amountIn1: 0,
      amountOut1Min: 0,
      swapData1: "",
      amountAddMin0: 0,
      amountAddMin1: 0,
      poolDeployer: address(0)
    });

    bytes memory strategyData = bytes.concat(
      abi.encode(SharedV3Strategy.OperationType.SWAP_AND_MINT),
      abi.encode(params, approveTokens, approveAmounts, uint256(0))
    );

    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] =
      ISharedVault.Action({ target: address(v3Strategy), data: strategyData, callType: ISharedCommon.CallType.DELEGATECALL });

    vm.prank(address(owner));
    SharedVault(payable(vault)).execute(actions);

    assertGt(SharedVault(payable(vault)).getPositionCount(), 0, "position should be open");

    // All players withdraw — LP should be exited proportionally
    owner.callWithdraw(vault, owner.sharesBalance(vault), false);
    player1.callWithdraw(vault, player1.sharesBalance(vault), false);
    player2.callWithdraw(vault, player2.sharesBalance(vault), false);

    assertEq(IERC20(vault).totalSupply(), 0, "all shares burned");
    assertEq(SharedVault(payable(vault)).getPositionCount(), 0, "all positions closed");
  }

  function test_allWithdrawAfterDeposit() public {
    owner.callWithdraw(vault, owner.sharesBalance(vault), false);
    player1.callWithdraw(vault, player1.sharesBalance(vault), false);
    player2.callWithdraw(vault, player2.sharesBalance(vault), false);
    assertEq(IERC20(vault).totalSupply(), 0);
    console.log("owner WETH after:", IERC20(SV_WETH).balanceOf(address(owner)));
    console.log("player1 WETH after:", IERC20(SV_WETH).balanceOf(address(player1)));
  }
}
