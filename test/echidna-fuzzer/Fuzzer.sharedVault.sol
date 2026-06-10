// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/*
 * SharedVault assertion-mode Echidna harness.
 *
 * This intentionally mixes stateful randomized flows with deterministic edge-case
 * scenarios. The goal is to complement the Forge shared-vault suite with
 * sequence fuzzing across the surfaces that matter for SharedVault accounting:
 *
 * - idle 2-token vault deposits/withdrawals, including excess-input deposits
 * - 4-token vaults with 18/18/6/8 decimal tokens
 * - fee-on-transfer and no-return ERC20 deposit paths
 * - native ETH -> WETH deposit/withdraw paths
 * - LP position valuation, proportional top-ups, previewWithdraw, and exits
 * - pause/min-output/invalid-ratio negative paths
 *
 * To run:
 *   ./run-echidna-test.sh SharedVaultFuzzer
 *
 * During development, a shorter direct run is useful:
 *   echidna test/echidna-fuzzer/Fuzzer.sharedVault.sol \
 *     --config test/echidna-fuzzer/config.yaml \
 *     --contract SharedVaultFuzzer --test-limit 1000 --seq-len 40
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./Config.sol";

import { SharedVault } from "../../contracts/shared-vault/core/SharedVault.sol";
import { SharedVaultGateway } from "../../contracts/shared-vault/core/SharedVaultGateway.sol";
import { SharedConfigManager } from "../../contracts/shared-vault/core/SharedConfigManager.sol";
import { ISharedCommon } from "../../contracts/shared-vault/interfaces/ISharedCommon.sol";
import { ISharedConfigManager } from "../../contracts/shared-vault/interfaces/ISharedConfigManager.sol";
import { ISharedStrategy } from "../../contracts/shared-vault/interfaces/ISharedStrategy.sol";
import { ISharedVault } from "../../contracts/shared-vault/interfaces/ISharedVault.sol";
import { SharedSwapDataSignature } from "../../contracts/shared-vault/libraries/SharedSwapDataSignature.sol";

contract FuzzERC20 {
  string public name;
  string public symbol;
  uint8 public decimals;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  constructor(string memory _name, string memory _symbol, uint8 _decimals) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
  }

  function mint(address to, uint256 amount) external virtual {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external virtual returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    _transfer(from, to, amount);
    return true;
  }

  function approve(address spender, uint256 amount) external virtual returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function _transfer(address from, address to, uint256 amount) internal virtual {
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
  }
}

contract FotERC20 is FuzzERC20 {
  uint256 public feeBps;

  constructor(uint256 _feeBps) FuzzERC20("FeeOnTransfer", "FOT", 18) {
    feeBps = _feeBps;
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    balanceOf[from] -= amount;
    uint256 fee = (amount * feeBps) / 10_000;
    uint256 received = amount - fee;
    balanceOf[to] += received;
    totalSupply -= fee;
  }
}

contract NoReturnERC20 {
  string public name = "NoReturn";
  string public symbol = "NRT";
  uint8 public decimals = 6;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  uint256 public totalSupply;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function transfer(address to, uint256 amount) external {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
  }

  function transferFrom(address from, address to, uint256 amount) external {
    if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
  }

  function approve(address spender, uint256 amount) external {
    allowance[msg.sender][spender] = amount;
  }
}

contract FuzzWETH9 is FuzzERC20 {
  constructor() FuzzERC20("Wrapped Ether", "WETH", 18) { }

  receive() external payable {
    deposit();
  }

  function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
    totalSupply += msg.value;
  }

  function withdraw(uint256 amount) external {
    balanceOf[msg.sender] -= amount;
    totalSupply -= amount;
    (bool ok,) = msg.sender.call{ value: amount }("");
    require(ok, "ETH transfer failed");
  }
}

contract FuzzERC721 {
  mapping(uint256 => address) public ownerOf;

  function mint(address to, uint256 tokenId) external {
    ownerOf[tokenId] = to;
  }

  function transferFrom(address from, address to, uint256 tokenId) public {
    require(ownerOf[tokenId] == from, "not owner");
    ownerOf[tokenId] = to;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    transferFrom(from, to, tokenId);
  }
}

contract SharedFuzzPlayer {
  SharedVault public vault;

  constructor(SharedVault _vault, address[4] memory toks) {
    vault = _vault;
    for (uint256 i; i < 4; i++) {
      if (toks[i] != address(0)) FuzzERC20(toks[i]).approve(address(_vault), type(uint256).max);
    }
  }

  receive() external payable { }

  function deposit(uint256[4] memory amounts, uint16 slippageBps) external payable returns (uint256 shares) {
    return vault.deposit{ value: msg.value }(amounts, slippageBps, 0);
  }

  function withdraw(uint256 shares, uint256[4] memory mins, bool unwrap) external returns (uint256[4] memory amounts) {
    return vault.withdraw(shares, mins, unwrap);
  }
}

contract SharedDelegatedWithdrawer {
  function withdrawFor(SharedVault vault, uint256 shares, uint256[4] memory mins, address account)
    external
    returns (uint256[4] memory amounts)
  {
    return vault.withdraw(shares, mins, false, account);
  }
}

contract FuzzSwapRouter {
  function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
    require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "pull failed");
    require(IERC20(tokenOut).transfer(msg.sender, amountOut), "push failed");
  }
}

contract FuzzSigner {
  bytes4 internal constant EIP1271_MAGIC = 0x1626ba7e;

  function isValidSignature(bytes32 hash, bytes memory signature) external pure returns (bytes4) {
    if (signature.length == 32 && abi.decode(signature, (bytes32)) == hash) return EIP1271_MAGIC;
    return 0xffffffff;
  }
}

contract FuzzLpPool {
  struct Position {
    address token0;
    address token1;
    uint256 principal0;
    uint256 principal1;
    uint256 rewards0;
    uint256 rewards1;
  }

  mapping(bytes32 => Position) internal positions;

  function deposit(address nfpm, uint256 tokenId, address token0, address token1, uint256 amount0, uint256 amount1)
    external
  {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    Position storage p = positions[key];
    if (p.token0 == address(0)) {
      p.token0 = token0;
      p.token1 = token1;
    }
    p.principal0 += amount0;
    p.principal1 += amount1;
  }

  function setRewards(address nfpm, uint256 tokenId, uint256 reward0, uint256 reward1) external {
    bytes32 key = keccak256(abi.encodePacked(nfpm, tokenId));
    positions[key].rewards0 = reward0;
    positions[key].rewards1 = reward1;
  }

  function getAmounts(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1) {
    Position storage p = positions[keccak256(abi.encodePacked(nfpm, tokenId))];
    return (p.principal0 + p.rewards0, p.principal1 + p.rewards1);
  }

  function getPrincipal(address nfpm, uint256 tokenId) external view returns (uint256 amount0, uint256 amount1) {
    Position storage p = positions[keccak256(abi.encodePacked(nfpm, tokenId))];
    return (p.principal0, p.principal1);
  }

  function hasPosition(address nfpm, uint256 tokenId) external view returns (bool) {
    Position storage p = positions[keccak256(abi.encodePacked(nfpm, tokenId))];
    return p.token0 != address(0);
  }

  function collectRewards(address nfpm, uint256 tokenId, address recipient) external {
    Position storage p = positions[keccak256(abi.encodePacked(nfpm, tokenId))];
    uint256 reward0 = p.rewards0;
    uint256 reward1 = p.rewards1;
    p.rewards0 = 0;
    p.rewards1 = 0;
    if (reward0 > 0) IERC20(p.token0).transfer(recipient, reward0);
    if (reward1 > 0) IERC20(p.token1).transfer(recipient, reward1);
  }

  function exit(address nfpm, uint256 tokenId, uint256 shares, uint256 totalShares, address recipient)
    external
    returns (bool fullyExited)
  {
    Position storage p = positions[keccak256(abi.encodePacked(nfpm, tokenId))];
    uint256 exit0 = (p.principal0 * shares) / totalShares;
    uint256 exit1 = (p.principal1 * shares) / totalShares;
    if (exit0 > 0) {
      p.principal0 -= exit0;
      IERC20(p.token0).transfer(recipient, exit0);
    }
    if (exit1 > 0) {
      p.principal1 -= exit1;
      IERC20(p.token1).transfer(recipient, exit1);
    }
    fullyExited = p.principal0 == 0 && p.principal1 == 0 && p.rewards0 == 0 && p.rewards1 == 0;
  }
}

contract FuzzLpStrategy is ISharedStrategy {
  FuzzLpPool public immutable pool;
  address public immutable nfpm;
  uint256 public immutable tokenId;
  address public immutable token0;
  address public immutable token1;

  constructor(FuzzLpPool _pool, address _nfpm, uint256 _tokenId, address _token0, address _token1) {
    pool = _pool;
    nfpm = _nfpm;
    tokenId = _tokenId;
    token0 = _token0;
    token1 = _token1;
  }

  function execute(bytes calldata data) external payable override returns (PositionChange[] memory changes) {
    (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
    if (pool.hasPosition(nfpm, tokenId)) _collectAndDistributeFees();
    if (amount0 > 0) IERC20(token0).transfer(address(pool), amount0);
    if (amount1 > 0) IERC20(token1).transfer(address(pool), amount1);
    pool.deposit(nfpm, tokenId, token0, token1, amount0, amount1);

    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  function depositProportional(address, uint256, uint256 amount0, uint256 amount1, uint16) external override {
    if (amount0 > 0) IERC20(token0).transfer(address(pool), amount0);
    if (amount1 > 0) IERC20(token1).transfer(address(pool), amount1);
    pool.deposit(nfpm, tokenId, token0, token1, amount0, amount1);
  }

  function exitProportional(address, uint256, uint256 shares, uint256 totalShares, uint256, uint256, uint16)
    external
    override
    returns (PositionChange[] memory changes)
  {
    bool fullyExited = pool.exit(nfpm, tokenId, shares, totalShares, address(this));
    if (fullyExited) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
    } else {
      changes = new PositionChange[](0);
    }
  }

  function collectFees(address, uint256, uint16) external override {
    _collectAndDistributeFees();
  }

  function getPositionAmounts(address, uint256) external view override returns (uint256 amount0, uint256 amount1) {
    return pool.getAmounts(nfpm, tokenId);
  }

  function getPositionPrincipalAmounts(address, uint256)
    external
    view
    override
    returns (uint256 amount0, uint256 amount1)
  {
    return pool.getPrincipal(nfpm, tokenId);
  }

  function getPositionAmountsSplit(address, uint256)
    external
    view
    override
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    (total0, total1) = pool.getAmounts(nfpm, tokenId);
    (principal0, principal1) = pool.getPrincipal(nfpm, tokenId);
  }

  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (token0, token1);
  }

  function _collectAndDistributeFees() private {
    uint256 before0 = IERC20(token0).balanceOf(address(this));
    uint256 before1 = IERC20(token1).balanceOf(address(this));
    pool.collectRewards(nfpm, tokenId, address(this));
    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - before0;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - before1;
    if (collected0 == 0 && collected1 == 0) return;

    ISharedVault v = ISharedVault(address(this));
    ISharedConfigManager cm = v.configManager();
    uint16 platformBps = cm.platformFeeBasisPoint();
    uint16 ownerBps = v.vaultOwnerFeeBasisPoint();
    uint16 maxOwnerBps = 10_000 - platformBps;
    if (ownerBps > maxOwnerBps) ownerBps = maxOwnerBps;

    _distributeFee(token0, collected0, cm.feeRecipient(), platformBps, v.vaultOwner(), ownerBps);
    _distributeFee(token1, collected1, cm.feeRecipient(), platformBps, v.vaultOwner(), ownerBps);
  }

  function _distributeFee(
    address token,
    uint256 amount,
    address platformRecipient,
    uint16 platformBps,
    address vaultOwner,
    uint16 ownerBps
  ) private {
    uint256 platformFee = _feeAmount(amount, platformBps);
    if (platformFee > 0) IERC20(token).transfer(platformRecipient, platformFee);

    uint256 ownerFee = _feeAmount(amount, ownerBps);
    if (ownerFee > 0) IERC20(token).transfer(vaultOwner, ownerFee);
  }

  function _feeAmount(uint256 amount, uint16 bps) private pure returns (uint256) {
    return (amount / 10_000) * bps + ((amount % 10_000) * bps) / 10_000;
  }
}

contract FuzzCwpTarget is ISharedStrategy {
  address public immutable token0;
  address public immutable token1;

  constructor(address _token0, address _token1) {
    token0 = _token0;
    token1 = _token1;
  }

  function createPosition(address nfpm, uint256 tokenId) external view returns (PositionChange[] memory changes) {
    changes = new PositionChange[](1);
    changes[0] = PositionChange({ isAdd: true, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
  }

  function execute(bytes calldata) external payable override returns (PositionChange[] memory changes) {
    changes = new PositionChange[](0);
  }

  function depositProportional(address, uint256, uint256, uint256, uint16) external override { }

  function exitProportional(
    address nfpm,
    uint256 tokenId,
    uint256 shares,
    uint256 totalShares,
    uint256,
    uint256,
    uint16
  ) external view override returns (PositionChange[] memory changes) {
    if (shares == totalShares) {
      changes = new PositionChange[](1);
      changes[0] = PositionChange({ isAdd: false, nfpm: nfpm, tokenId: tokenId, token0: token0, token1: token1 });
    } else {
      changes = new PositionChange[](0);
    }
  }

  function collectFees(address, uint256, uint16) external override { }

  function getPositionAmounts(address, uint256) external pure override returns (uint256 amount0, uint256 amount1) {
    return (0, 0);
  }

  function getPositionPrincipalAmounts(address, uint256)
    external
    pure
    override
    returns (uint256 amount0, uint256 amount1)
  {
    return (0, 0);
  }

  function getPositionAmountsSplit(address, uint256)
    external
    pure
    override
    returns (uint256 total0, uint256 total1, uint256 principal0, uint256 principal1)
  {
    return (0, 0, 0, 0);
  }

  function getPositionTokens(address, uint256) external view override returns (address, address) {
    return (token0, token1);
  }
}

contract SharedVaultFuzzer {
  uint256 internal constant INITIAL_SHARES = 10e18;
  uint256 internal constant MAX_18 = 1e21;
  uint256 internal constant MAX_6 = 1e9;
  uint256 internal constant MAX_8 = 1e10;

  SharedConfigManager public configManager;

  SharedVault public idleVault;
  FuzzERC20 public idleA;
  FuzzERC20 public idleB;
  SharedFuzzPlayer[3] public idlePlayers;

  SharedVault public multiVault;
  FuzzERC20 public multiA;
  FuzzERC20 public multiB;
  FuzzERC20 public multiC;
  FuzzERC20 public multiD;
  SharedFuzzPlayer[2] public multiPlayers;

  SharedVault public lpVault;
  FuzzERC20 public lpA;
  FuzzERC20 public lpB;
  FuzzLpPool public lpPool;
  FuzzERC721 public lpNfpm;
  FuzzLpStrategy public lpStrategy;
  FuzzLpStrategy public lpStrategy2;
  SharedFuzzPlayer public lpPlayer;

  SharedVault public wethVault;
  FuzzERC20 public wethTokenA;
  FuzzWETH9 public weth;
  SharedFuzzPlayer public wethPlayer;

  SharedConfigManager public precisionConfigManager;
  SharedVault public precisionVault;
  FuzzERC20 public precisionA;
  FuzzERC20 public precisionB;
  FuzzERC20 public precisionX;
  SharedVaultGateway public gateway;
  SharedDelegatedWithdrawer public delegatedWithdrawer;

  // Fee-bearing stateful vault: platform fee 10% + vault-owner fee 5% on collected LP rewards.
  // Every other stateful vault runs with zero fees, so this one is the only sequence-fuzzed
  // coverage of the fee-netted valuation (computeTotalBalances / previewWithdraw netFees branch)
  // and of collect-during-withdraw fee distribution.
  SharedConfigManager public feeConfigManager;
  SharedVault public feeVault;
  FuzzERC20 public feeA;
  FuzzERC20 public feeB;
  FuzzLpPool public feePool;
  FuzzERC721 public feeNfpm;
  FuzzLpStrategy public feeStrategy;
  SharedFuzzPlayer public feePlayer;
  uint256 internal constant FEE_TOKEN_ID = 11;
  address internal constant FEE_PLATFORM_RECIPIENT = address(0xFEE1);
  address internal constant FEE_VAULT_OWNER = address(0xFEE2);

  FuzzSwapRouter public swapRouter;
  FuzzSigner public swapDataSigner;
  uint256 internal swapDataNonce;

  bool public fullLpExitChecked;
  bool public fotChecked;
  bool public noReturnChecked;
  bool public pauseChecked;
  bool public callTypeChecked;
  bool public delegatedWithdrawChecked;
  bool public gatewayFotChecked;

  constructor() payable {
    swapRouter = new FuzzSwapRouter();
    swapDataSigner = new FuzzSigner();
    delegatedWithdrawer = new SharedDelegatedWithdrawer();
    configManager = _newConfig(new address[](0), new address[](0));
    _whitelistSwapRouter(configManager, address(swapRouter));

    _setupIdleVault();
    _setupMultiVault();
    _setupLpVault();
    _setupWethVault();
    _setupPrecisionGatewayVault();
    _setupFeeVault();
  }

  receive() external payable { }

  // -------------------------------------------------------------------------
  // Stateful idle 2-token vault
  // -------------------------------------------------------------------------

  function idle_deposit(uint8 idx, uint256 amountA, uint256 amountB) external {
    idx = idx % 3;
    amountA = _bound(amountA, 0, MAX_18);
    amountB = _bound(amountB, 0, MAX_18 * 2);

    uint256[4] memory amounts = [amountA, amountB, uint256(0), uint256(0)];
    uint256 preview = idleVault.previewDeposit(amounts);
    uint256 supplyBefore = idleVault.totalSupply();
    uint256 sharesBefore = idleVault.balanceOf(address(idlePlayers[idx]));
    uint256 balABefore = idleA.balanceOf(address(idleVault));
    uint256 balBBefore = idleB.balanceOf(address(idleVault));

    try idlePlayers[idx].deposit(amounts, 0) returns (uint256 shares) {
      assert(preview > 0);
      assert(shares == preview);
      assert(idleVault.totalSupply() == supplyBefore + shares);
      assert(idleVault.balanceOf(address(idlePlayers[idx])) == sharesBefore + shares);
      assert(idleA.balanceOf(address(idleVault)) >= balABefore);
      assert(idleB.balanceOf(address(idleVault)) >= balBBefore);
    } catch {
      assert(preview == 0);
    }

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  function idle_withdraw(uint8 idx, uint256 shareSeed) external {
    idx = idx % 3;
    uint256 bal = idleVault.balanceOf(address(idlePlayers[idx]));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256 supplyBefore = idleVault.totalSupply();
    uint256[4] memory preview = idleVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;

    uint256[4] memory mins;
    try idlePlayers[idx].withdraw(shares, mins, false) returns (uint256[4] memory got) {
      assert(_hasAnyOutput(got));
      assert(got[0] == preview[0]);
      assert(got[1] == preview[1]);
      assert(idleVault.totalSupply() == supplyBefore - shares);
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  function idle_delegated_withdraw_spends_allowance(uint256 shareSeed, bool infiniteAllowance) external {
    uint256 bal = idleVault.balanceOf(address(this));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256[4] memory preview = idleVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;

    uint256 allowanceAmount = infiniteAllowance ? type(uint256).max : shares;
    idleVault.approve(address(delegatedWithdrawer), allowanceAmount);

    uint256 supplyBefore = idleVault.totalSupply();
    uint256 aBefore = idleA.balanceOf(address(delegatedWithdrawer));
    uint256 bBefore = idleB.balanceOf(address(delegatedWithdrawer));
    uint256[4] memory mins;

    try delegatedWithdrawer.withdrawFor(idleVault, shares, mins, address(this)) returns (uint256[4] memory got) {
      assert(got[0] == preview[0]);
      assert(got[1] == preview[1]);
      assert(idleVault.totalSupply() == supplyBefore - shares);
      assert(idleA.balanceOf(address(delegatedWithdrawer)) == aBefore + got[0]);
      assert(idleB.balanceOf(address(delegatedWithdrawer)) == bBefore + got[1]);
      if (infiniteAllowance) {
        assert(idleVault.allowance(address(this), address(delegatedWithdrawer)) == type(uint256).max);
      } else {
        assert(idleVault.allowance(address(this), address(delegatedWithdrawer)) == 0);
      }
      delegatedWithdrawChecked = true;
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  function idle_withdraw_allowed_while_paused(uint256 shareSeed, bool globalPause) external {
    uint256 bal = idleVault.balanceOf(address(this));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256[4] memory preview = idleVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;

    if (globalPause) configManager.setVaultPaused(true);
    else idleVault.setPaused(true);

    uint256[4] memory mins;
    try idleVault.withdraw(shares, mins, false) returns (uint256[4] memory got) {
      assert(got[0] == preview[0]);
      assert(got[1] == preview[1]);
      pauseChecked = true;
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    if (globalPause) configManager.setVaultPaused(false);
    else idleVault.setPaused(false);

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  function idle_invalid_missing_active_token_reverts(uint256 amountA) external {
    amountA = _bound(amountA, 1e13, MAX_18);
    uint256[4] memory amounts = [amountA, uint256(0), uint256(0), uint256(0)];
    uint256 preview = idleVault.previewDeposit(amounts);

    try idlePlayers[0].deposit(amounts, 0) returns (uint256) {
      assert(preview > 0);
      // If the vault state ever makes token B inactive, this can be valid. In
      // the normal seeded path it must remain an invalid-ratio deposit.
      uint256[4] memory totals = idleVault.getTotalBalances();
      assert(totals[1] == 0);
    } catch {
      assert(preview == 0);
    }
  }

  // -------------------------------------------------------------------------
  // Stateful 4-token vault, low decimals included
  // -------------------------------------------------------------------------

  function multi_deposit(uint8 idx, uint256 amountA) external {
    idx = idx % 2;
    amountA = _bound(amountA, 1e13, MAX_18);

    uint256[4] memory totals = multiVault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0 || totals[2] == 0 || totals[3] == 0) return;

    uint256[4] memory amounts;
    amounts[0] = amountA;
    amounts[1] = _ceilMulDiv(amountA, totals[1], totals[0]);
    amounts[2] = _ceilMulDiv(amountA, totals[2], totals[0]);
    amounts[3] = _ceilMulDiv(amountA, totals[3], totals[0]);
    if (amounts[1] > MAX_18 || amounts[2] > MAX_6 || amounts[3] > MAX_8) return;

    uint256 preview = multiVault.previewDeposit(amounts);
    uint256 supplyBefore = multiVault.totalSupply();
    try multiPlayers[idx].deposit(amounts, 0) returns (uint256 shares) {
      assert(preview > 0);
      assert(shares == preview);
      assert(multiVault.totalSupply() == supplyBefore + shares);
    } catch {
      assert(preview == 0);
    }

    _assertMultiShareConservation();
    _assertPositiveBacking(multiVault);
  }

  function multi_withdraw(uint8 idx, uint256 shareSeed) external {
    idx = idx % 2;
    uint256 bal = multiVault.balanceOf(address(multiPlayers[idx]));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256[4] memory preview = multiVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;
    uint256 supplyBefore = multiVault.totalSupply();
    uint256[4] memory mins;

    try multiPlayers[idx].withdraw(shares, mins, false) returns (uint256[4] memory got) {
      assert(_hasAnyOutput(got));
      assert(got[0] == preview[0]);
      assert(got[1] == preview[1]);
      assert(got[2] == preview[2]);
      assert(got[3] == preview[3]);
      assert(multiVault.totalSupply() == supplyBefore - shares);
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    _assertMultiShareConservation();
    _assertPositiveBacking(multiVault);
  }

  function multi_missing_fourth_token_reverts(uint256 amountA) external {
    amountA = _bound(amountA, 1e13, MAX_18);
    uint256[4] memory totals = multiVault.getTotalBalances();
    if (totals[3] == 0) return;

    uint256[4] memory amounts;
    amounts[0] = amountA;
    amounts[1] = _ceilMulDiv(amountA, totals[1], totals[0]);
    amounts[2] = _ceilMulDiv(amountA, totals[2], totals[0]);
    amounts[3] = 0;

    try multiPlayers[0].deposit(amounts, 0) returns (uint256) {
      assert(false);
    } catch { }
  }

  // -------------------------------------------------------------------------
  // Stateful LP vault
  // -------------------------------------------------------------------------

  function lp_deposit(uint256 amountA) external {
    amountA = _bound(amountA, 1e13, MAX_18);
    uint256[4] memory totals = lpVault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256[4] memory amounts;
    amounts[0] = amountA;
    amounts[1] = _ceilMulDiv(amountA, totals[1], totals[0]);
    if (amounts[1] > MAX_18) return;

    uint256 preview = lpVault.previewDeposit(amounts);
    uint256 supplyBefore = lpVault.totalSupply();
    uint256 posBefore = lpVault.getPositionCount();
    (uint256 principal0Before, uint256 principal1Before) = lpPool.getPrincipal(address(lpNfpm), 1);
    (uint256 p2Principal0Before, uint256 p2Principal1Before) = lpPool.getPrincipal(address(lpNfpm), 2);

    try lpPlayer.deposit(amounts, 100) returns (uint256 shares) {
      assert(preview > 0);
      assert(shares > 0);
      assert(lpVault.totalSupply() == supplyBefore + shares);
      assert(lpVault.getPositionCount() == posBefore);
      (uint256 principal0After, uint256 principal1After) = lpPool.getPrincipal(address(lpNfpm), 1);
      assert(principal0After >= principal0Before);
      assert(principal1After >= principal1Before);
      (uint256 p2Principal0After, uint256 p2Principal1After) = lpPool.getPrincipal(address(lpNfpm), 2);
      assert(p2Principal0After >= p2Principal0Before);
      assert(p2Principal1After >= p2Principal1Before);
    } catch {
      assert(preview == 0);
    }

    _assertLpShareConservation();
    _assertPositiveBacking(lpVault);
  }

  /// @dev Operator emergency flows: dropPosition must untrack the position and hand the NFT to the
  ///      operator without burning shares; recoverPosition must re-track it and pull the NFT back.
  ///      The vault must stay backed and share-conserving through the round trip. The harness is both
  ///      vault owner and operator, so both legs run in one call and external state is fully restored.
  function lp_drop_and_recover_position_keeps_vault_backed(uint256 posSeed) external {
    uint256 count = lpVault.getPositionCount();
    if (count == 0) return;

    uint256 idx = posSeed % count;
    (address strategy, address nfpm, uint256 tokenId, address token0, address token1) = lpVault.getPosition(idx);
    uint256 supplyBefore = lpVault.totalSupply();

    lpVault.dropPosition(nfpm, tokenId);
    assert(lpVault.getPositionCount() == count - 1);
    // Operator is set (this harness), so the NFT must have been transferred out to it.
    assert(FuzzERC721(nfpm).ownerOf(tokenId) == address(this));
    assert(lpVault.totalSupply() == supplyBefore);
    _assertLpShareConservation();
    _assertPositiveBacking(lpVault);

    lpVault.recoverPosition(nfpm, tokenId, strategy, token0, token1);
    assert(lpVault.getPositionCount() == count);
    assert(FuzzERC721(nfpm).ownerOf(tokenId) == address(lpVault));
    assert(lpVault.totalSupply() == supplyBefore);
    _assertLpShareConservation();
    _assertPositiveBacking(lpVault);
  }

  function lp_withdraw(uint256 shareSeed) external {
    uint256 bal = lpVault.balanceOf(address(lpPlayer));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256[4] memory preview = lpVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;
    uint256 supplyBefore = lpVault.totalSupply();
    uint256[4] memory mins;

    uint256 tolerance = lpVault.getPositionCount();
    try lpPlayer.withdraw(shares, mins, false) returns (uint256[4] memory got) {
      assert(_hasAnyOutput(got));
      assert(_withinUnits(got[0], preview[0], tolerance));
      assert(_withinUnits(got[1], preview[1], tolerance));
      assert(lpVault.totalSupply() == supplyBefore - shares);
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    _assertLpShareConservation();
    _assertPositiveBacking(lpVault);
  }

  /// @dev Two tracked positions so the full exit walks SharedVault._withdraw's swap-with-last loop:
  ///      removing index 0 swaps the last position into its slot, which must then be processed at the
  ///      SAME index (the `!removed → don't advance p` branch) — with one position that branch is dead.
  function lp_owner_full_exit_removes_position() external {
    if (fullLpExitChecked) return;
    fullLpExitChecked = true;

    SharedConfigManager cm = _newConfig(new address[](0), new address[](0));
    FuzzERC20 t0 = new FuzzERC20("FullLpA", "FLA", 18);
    FuzzERC20 t1 = new FuzzERC20("FullLpB", "FLB", 18);
    FuzzERC721 nfpm = new FuzzERC721();
    FuzzLpPool pool = new FuzzLpPool();
    FuzzLpStrategy strategy = new FuzzLpStrategy(pool, address(nfpm), 99, address(t0), address(t1));
    FuzzLpStrategy strategy2 = new FuzzLpStrategy(pool, address(nfpm), 100, address(t0), address(t1));
    _whitelist(cm, address(strategy), address(nfpm));
    _whitelist(cm, address(strategy2), address(nfpm));

    SharedVault v = new SharedVault();
    t0.mint(address(v), 100e18);
    t1.mint(address(v), 100e18);
    address[4] memory toks = [address(t0), address(t1), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    v.initialize("FullExit", toks, init, address(this), address(this), address(cm), address(0), 0);

    nfpm.mint(address(v), 99);
    nfpm.mint(address(v), 100);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action({
      target: address(strategy),
      data: abi.encode(uint256(50e18), uint256(50e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    actions[1] = ISharedVault.Action({
      target: address(strategy2),
      data: abi.encode(uint256(25e18), uint256(10e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    v.execute(actions);
    assert(v.getPositionCount() == 2);

    uint256 shares = v.balanceOf(address(this));
    uint256[4] memory mins;
    uint256[4] memory got = v.withdraw(shares, mins, false);
    assert(got[0] > 0 && got[1] > 0);
    assert(v.totalSupply() == 0);
    assert(v.getPositionCount() == 0);
  }

  function lp_generated_fee_distribution(uint256 reward0, uint256 reward1, uint16 rawPlatformBps, uint16 rawOwnerBps)
    external
  {
    reward0 = _bound(reward0, 0, type(uint256).max / 4);
    reward1 = _bound(reward1, 0, type(uint256).max / 4);
    uint16 platformBps = rawPlatformBps % 10_001;
    uint16 ownerBps = rawOwnerBps % 10_001;
    uint16 effectiveOwnerBps = ownerBps;
    uint16 maxOwnerBps = 10_000 - platformBps;
    if (effectiveOwnerBps > maxOwnerBps) effectiveOwnerBps = maxOwnerBps;

    address platformRecipient = address(0xBEEF);
    address ownerRecipient = address(0xCAFE);
    SharedConfigManager cm = new SharedConfigManager();
    address[] memory empty = new address[](0);
    address[] memory callers = new address[](1);
    callers[0] = address(this);
    cm.initialize(address(this), empty, callers, platformRecipient, platformBps, empty, empty, empty);

    FuzzERC20 t0 = new FuzzERC20("GeneratedFeeA", "GFA", 18);
    FuzzERC20 t1 = new FuzzERC20("GeneratedFeeB", "GFB", 18);
    FuzzERC721 nfpm = new FuzzERC721();
    FuzzLpPool pool = new FuzzLpPool();
    FuzzLpStrategy strategy = new FuzzLpStrategy(pool, address(nfpm), 707, address(t0), address(t1));
    _whitelist(cm, address(strategy), address(nfpm));

    SharedVault v = new SharedVault();
    t0.mint(address(v), 100e18);
    t1.mint(address(v), 100e18);
    address[4] memory toks = [address(t0), address(t1), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    v.initialize("GeneratedFees", toks, init, ownerRecipient, address(0), address(cm), address(0), ownerBps);

    nfpm.mint(address(v), 707);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(strategy),
      data: abi.encode(uint256(50e18), uint256(50e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    v.execute(actions);

    uint256 vault0Before = t0.balanceOf(address(v));
    uint256 vault1Before = t1.balanceOf(address(v));
    t0.mint(address(pool), reward0);
    t1.mint(address(pool), reward1);
    pool.setRewards(address(nfpm), 707, reward0, reward1);

    actions[0] = ISharedVault.Action({
      target: address(strategy), data: abi.encode(uint256(0), uint256(0)), callType: ISharedCommon.CallType.DELEGATECALL
    });
    v.execute(actions);

    uint256 platformFee0 = _feeAmount(reward0, platformBps);
    uint256 platformFee1 = _feeAmount(reward1, platformBps);
    uint256 ownerFee0 = _feeAmount(reward0, effectiveOwnerBps);
    uint256 ownerFee1 = _feeAmount(reward1, effectiveOwnerBps);

    assert(t0.balanceOf(platformRecipient) == platformFee0);
    assert(t1.balanceOf(platformRecipient) == platformFee1);
    assert(t0.balanceOf(ownerRecipient) == ownerFee0);
    assert(t1.balanceOf(ownerRecipient) == ownerFee1);
    assert(t0.balanceOf(address(v)) == vault0Before + reward0 - platformFee0 - ownerFee0);
    assert(t1.balanceOf(address(v)) == vault1Before + reward1 - platformFee1 - ownerFee1);
  }

  // -------------------------------------------------------------------------
  // Deterministic token/WETH/permission edge cases
  // -------------------------------------------------------------------------

  function token_edges_fot_and_no_return() external {
    if (fotChecked) return;
    fotChecked = true;

    FotERC20 fot = new FotERC20(200);
    FotERC20 fot100 = new FotERC20(10_000);
    FuzzERC20 standard = new FuzzERC20("Standard", "STD", 18);

    SharedVault partialVault = new SharedVault();
    address[4] memory partialToks = [address(fot), address(standard), address(0), address(0)];
    uint256[4] memory zeroInit;
    partialVault.initialize(
      "PartialFOT", partialToks, zeroInit, address(this), address(this), address(configManager), address(0), 0
    );

    fot.mint(address(this), 1000e18);
    standard.mint(address(this), 1000e18);
    fot.approve(address(partialVault), type(uint256).max);
    standard.approve(address(partialVault), type(uint256).max);
    uint256 shares = partialVault.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0, 0);
    assert(shares == INITIAL_SHARES);
    assert(fot.balanceOf(address(partialVault)) == 98e18);

    SharedVault blocked = new SharedVault();
    address[4] memory blockedToks = [address(fot100), address(standard), address(0), address(0)];
    blocked.initialize(
      "BlockedFOT", blockedToks, zeroInit, address(this), address(this), address(configManager), address(0), 0
    );
    fot100.mint(address(this), 1000e18);
    fot100.approve(address(blocked), type(uint256).max);
    standard.approve(address(blocked), type(uint256).max);
    try blocked.deposit([uint256(100e18), uint256(100e18), uint256(0), uint256(0)], 0, 0) returns (uint256) {
      assert(false);
    } catch { }
  }

  function token_edges_no_return_erc20() external {
    if (noReturnChecked) return;
    noReturnChecked = true;

    NoReturnERC20 nrt = new NoReturnERC20();
    FuzzERC20 standard = new FuzzERC20("Standard2", "STD2", 18);
    SharedVault v = new SharedVault();
    address[4] memory toks = [address(nrt), address(standard), address(0), address(0)];
    uint256[4] memory init;
    v.initialize("NoReturn", toks, init, address(this), address(this), address(configManager), address(0), 0);

    nrt.mint(address(this), 1000e6);
    standard.mint(address(this), 1000e18);
    nrt.approve(address(v), type(uint256).max);
    standard.approve(address(v), type(uint256).max);
    uint256 shares = v.deposit([uint256(100e6), uint256(100e18), uint256(0), uint256(0)], 0, 0);
    assert(shares == INITIAL_SHARES);
    assert(nrt.balanceOf(address(v)) == 100e6);
  }

  function gateway_fee_on_transfer_deposit_credits_actual_receipt() external {
    if (gatewayFotChecked) return;
    gatewayFotChecked = true;

    SharedVaultGateway localGateway = new SharedVaultGateway();
    localGateway.initialize(address(this), address(swapRouter), address(weth));

    FotERC20 fot = new FotERC20(200);
    FuzzERC20 standard = new FuzzERC20("GatewayFOTPair", "GFP", 18);
    SharedVault v = new SharedVault();

    fot.mint(address(this), 100e18);
    standard.mint(address(this), 100e18);
    fot.transfer(address(v), 100e18);
    standard.transfer(address(v), 100e18);

    address[4] memory toks = [address(fot), address(standard), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    v.initialize("GatewayFOT", toks, init, address(this), address(this), address(configManager), address(0), 0);

    fot.mint(address(this), 50e18);
    standard.mint(address(this), 50e18);
    fot.approve(address(localGateway), type(uint256).max);
    standard.approve(address(localGateway), type(uint256).max);

    SharedVaultGateway.InputToken[] memory inputs = _gatewayInputs2(address(fot), 50e18, address(standard), 50e18);
    address[] memory sweepTokens = new address[](2);
    sweepTokens[0] = address(fot);
    sweepTokens[1] = address(standard);

    uint256 fotBefore = fot.balanceOf(address(v));
    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(v)),
      inputs: inputs,
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      slippageBps: 0,
      minShares: 0,
      sweepTokens: sweepTokens
    });

    uint256 shares = localGateway.swapAndDeposit(params);
    assert(shares > 0);
    assert(v.balanceOf(address(this)) > INITIAL_SHARES);
    assert(fot.balanceOf(address(v)) - fotBefore == (49e18 * 9800) / 10_000);
    assert(fot.balanceOf(address(localGateway)) == 0);
    assert(standard.balanceOf(address(localGateway)) == 0);
  }

  function execute_call_and_call_with_positions_paths() external {
    if (callTypeChecked) return;
    callTypeChecked = true;

    uint256 amountIn = 10e18;
    uint256 amountOut = 9e18;
    idleB.mint(address(swapRouter), amountOut);

    uint256 balABefore = idleA.balanceOf(address(idleVault));
    uint256 balBBefore = idleB.balanceOf(address(idleVault));

    bytes memory swapCalldata =
      abi.encodeCall(FuzzSwapRouter.swap, (address(idleA), address(idleB), amountIn, amountOut));
    swapCalldata = _signedSwapData(
      idleVault, address(swapRouter), address(idleA), address(idleB), amountIn, amountOut, swapCalldata
    );
    bytes memory actionData = abi.encode(address(idleA), address(idleB), amountIn, amountOut, swapCalldata);

    ISharedVault.Action[] memory callActions = new ISharedVault.Action[](1);
    callActions[0] =
      ISharedVault.Action({ target: address(swapRouter), data: actionData, callType: ISharedCommon.CallType.CALL });
    idleVault.execute(callActions);

    assert(idleA.balanceOf(address(idleVault)) == balABefore - amountIn);
    assert(idleB.balanceOf(address(idleVault)) == balBBefore + amountOut);
    assert(idleA.allowance(address(idleVault), address(swapRouter)) == 0);

    FuzzERC20 cwpA = new FuzzERC20("CwpA", "CWPA", 18);
    FuzzERC20 cwpB = new FuzzERC20("CwpB", "CWPB", 18);
    FuzzERC721 cwpNfpm = new FuzzERC721();
    FuzzCwpTarget cwpTarget = new FuzzCwpTarget(address(cwpA), address(cwpB));

    SharedConfigManager cm = _newConfig(new address[](0), new address[](0));
    _whitelist(cm, address(cwpTarget), address(cwpNfpm));

    SharedVault cwpVault = new SharedVault();
    cwpA.mint(address(cwpVault), 100e18);
    cwpB.mint(address(cwpVault), 100e18);
    address[4] memory toks = [address(cwpA), address(cwpB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    cwpVault.initialize("CwpShared", toks, init, address(this), address(this), address(cm), address(0), 0);

    uint256 tokenId = 7001;
    cwpNfpm.mint(address(cwpVault), tokenId);
    ISharedVault.Action[] memory cwpActions = new ISharedVault.Action[](1);
    cwpActions[0] = ISharedVault.Action({
      target: address(cwpTarget),
      data: abi.encodeCall(FuzzCwpTarget.createPosition, (address(cwpNfpm), tokenId)),
      callType: ISharedCommon.CallType.CALL_WITH_POSITIONS
    });
    cwpVault.execute(cwpActions);

    assert(cwpVault.getPositionCount() == 1);
    (address strategy, address nfpm, uint256 trackedTokenId, address token0, address token1) = cwpVault.getPosition(0);
    assert(strategy == address(cwpTarget));
    assert(nfpm == address(cwpNfpm));
    assert(trackedTokenId == tokenId);
    assert(token0 == address(cwpA));
    assert(token1 == address(cwpB));

    uint256 shares = cwpVault.balanceOf(address(this));
    uint256[4] memory mins;
    uint256[4] memory got = cwpVault.withdraw(shares, mins, false);
    assert(got[0] > 0 && got[1] > 0);
    assert(cwpVault.totalSupply() == 0);
    assert(cwpVault.getPositionCount() == 0);

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  function weth_native_deposit_withdraw(uint256 amount) external {
    amount = _bound(amount, 1e13, 10 ether);
    uint256[4] memory totals = wethVault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256[4] memory amounts;
    amounts[0] = _ceilMulDiv(amount, totals[0], totals[1]);
    amounts[1] = amount;
    if (amounts[0] > MAX_18) return;

    wethTokenA.mint(address(wethPlayer), amounts[0]);
    uint256 sharesBefore = wethVault.balanceOf(address(wethPlayer));
    try wethPlayer.deposit{ value: amount }(amounts, 0) returns (uint256 shares) {
      assert(shares > 0);
      assert(wethVault.balanceOf(address(wethPlayer)) == sharesBefore + shares);
    } catch {
      assert(false);
    }

    uint256 playerShares = wethVault.balanceOf(address(wethPlayer));
    uint256 burn = playerShares / 2;
    if (burn == 0) return;
    uint256 ethBefore = address(wethPlayer).balance;
    uint256[4] memory preview = wethVault.previewWithdraw(burn);
    if (!_hasNonDustOutput(preview)) return;
    uint256[4] memory mins;
    try wethPlayer.withdraw(burn, mins, true) returns (uint256[4] memory got) {
      assert(_hasAnyOutput(got));
      assert(got[1] == preview[1]);
      assert(address(wethPlayer).balance == ethBefore + got[1]);
    } catch {
      assert(false);
    }
  }

  function pause_and_min_output_edges() external {
    if (pauseChecked) return;
    pauseChecked = true;

    idleVault.setPaused(true);
    uint256[4] memory amounts = [uint256(1e18), uint256(2e18), uint256(0), uint256(0)];
    try idlePlayers[0].deposit(amounts, 0) returns (uint256) {
      assert(false);
    } catch { }
    idleVault.setPaused(false);

    uint256 bal = idleVault.balanceOf(address(idlePlayers[0]));
    if (bal == 0) {
      idlePlayers[0].deposit(amounts, 0);
      bal = idleVault.balanceOf(address(idlePlayers[0]));
    }
    uint256[4] memory mins = [uint256(type(uint256).max), uint256(0), uint256(0), uint256(0)];
    try idlePlayers[0].withdraw(bal / 2, mins, false) returns (uint256[4] memory) {
      assert(false);
    } catch { }
  }

  // -------------------------------------------------------------------------
  // minTokenPrecision and gateway edge cases
  // -------------------------------------------------------------------------

  function precision_config_8decimals(uint8 rawPrecision) external {
    uint8 precision = uint8(_bound(rawPrecision, 0, 12));
    precisionConfigManager.setMinTokenPrecision(precision);

    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    uint256 expected;
    if (precision == 0) expected = 0;
    else if (precision < 8) expected = 10 ** uint256(8 - precision);
    else expected = 1;
    assert(mins[1] == expected);

    precisionConfigManager.setMinTokenPrecision(5);
  }

  function precision_direct_deposit_floor(uint8 mode) external {
    precisionConfigManager.setMinTokenPrecision(5);
    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    if (mins[0] == 0 || mins[1] <= 1) return;

    if (mode % 2 == 0) {
      precisionA.mint(address(this), mins[0]);
      precisionB.mint(address(this), mins[1] - 1);
      uint256[4] memory below = [mins[0], mins[1] - 1, uint256(0), uint256(0)];
      try precisionVault.deposit(below, 0, 0) returns (uint256) {
        assert(false);
      } catch { }
      return;
    }

    precisionA.mint(address(this), mins[0]);
    precisionB.mint(address(this), mins[1]);
    uint256 vaultBBefore = precisionB.balanceOf(address(precisionVault));
    uint256 sharesBefore = precisionVault.balanceOf(address(this));
    uint256[4] memory exact = [mins[0], mins[1], uint256(0), uint256(0)];

    try precisionVault.deposit(exact, 0, 0) returns (uint256 shares) {
      assert(shares > 0);
      assert(precisionVault.balanceOf(address(this)) == sharesBefore + shares);
      assert(precisionB.balanceOf(address(precisionVault)) == vaultBBefore + mins[1]);
    } catch {
      assert(false);
    }

    _assertPrecisionShareConservation();
    _assertPositiveBacking(precisionVault);
  }

  function precision_withdraw_forwards_below_floor() external {
    precisionConfigManager.setMinTokenPrecision(5);
    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    if (mins[1] <= 1) return;

    uint256 shares = _belowFloorWithdrawShares(precisionVault, mins[1]);
    if (shares == 0 || shares > precisionVault.balanceOf(address(this))) return;

    uint256[4] memory preview = precisionVault.previewWithdraw(shares);
    if (preview[1] == 0 || preview[1] >= mins[1]) return;

    uint256 bBefore = precisionB.balanceOf(address(this));
    uint256[4] memory emptyMins;
    try precisionVault.withdraw(shares, emptyMins, false) returns (uint256[4] memory got) {
      assert(got[1] == preview[1]);
      assert(got[1] < mins[1]);
      assert(precisionB.balanceOf(address(this)) == bBefore + got[1]);
    } catch {
      assert(false);
    }

    _assertPrecisionShareConservation();
    _assertPositiveBacking(precisionVault);
  }

  function gateway_direct_deposit_precision_floor(uint8 mode) external {
    precisionConfigManager.setMinTokenPrecision(5);
    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    if (mins[0] == 0 || mins[1] <= 1) return;

    if (mode % 2 == 0) {
      precisionA.mint(address(this), mins[0]);
      precisionB.mint(address(this), mins[1] - 1);
      SharedVaultGateway.SwapAndDepositParams memory below = SharedVaultGateway.SwapAndDepositParams({
        vault: ISharedVault(address(precisionVault)),
        inputs: _gatewayInputs2(address(precisionA), mins[0], address(precisionB), mins[1] - 1),
        swaps: new SharedVaultGateway.SwapParams[](0),
        minDepositAmounts: [mins[0], mins[1] - 1, uint256(0), uint256(0)],
        slippageBps: 0,
        minShares: 0,
        sweepTokens: new address[](0)
      });
      try gateway.swapAndDeposit(below) returns (uint256) {
        assert(false);
      } catch { }
      return;
    }

    precisionA.mint(address(this), mins[0]);
    precisionB.mint(address(this), mins[1]);
    uint256 sharesBefore = precisionVault.balanceOf(address(this));
    uint256 vaultBBefore = precisionB.balanceOf(address(precisionVault));
    SharedVaultGateway.SwapAndDepositParams memory exact = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(precisionVault)),
      inputs: _gatewayInputs2(address(precisionA), mins[0], address(precisionB), mins[1]),
      swaps: new SharedVaultGateway.SwapParams[](0),
      minDepositAmounts: mins,
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    try gateway.swapAndDeposit(exact) returns (uint256 shares) {
      assert(shares > 0);
      assert(precisionVault.balanceOf(address(this)) == sharesBefore + shares);
      assert(precisionB.balanceOf(address(precisionVault)) == vaultBBefore + mins[1]);
      assert(precisionA.balanceOf(address(gateway)) == 0);
      assert(precisionB.balanceOf(address(gateway)) == 0);
    } catch {
      assert(false);
    }

    _assertPrecisionShareConservation();
    _assertPositiveBacking(precisionVault);
  }

  function gateway_swapAndDeposit_precision_floor(uint8 mode) external {
    precisionConfigManager.setMinTokenPrecision(5);
    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    if (mins[0] == 0 || mins[1] <= 1) return;

    bool belowFloor = mode % 2 == 0;
    uint256 outB = belowFloor ? mins[1] - 1 : mins[1];
    uint256 inA = 1e18;
    uint256 inB = 1e18;

    precisionX.mint(address(this), inA + inB);
    precisionA.mint(address(swapRouter), mins[0]);
    precisionB.mint(address(swapRouter), outB);

    SharedVaultGateway.SwapParams[] memory swaps = new SharedVaultGateway.SwapParams[](2);
    swaps[0] = SharedVaultGateway.SwapParams({
      tokenIn: address(precisionX),
      amountIn: inA,
      tokenOut: address(precisionA),
      amountOutMin: mins[0],
      swapData: abi.encodeCall(FuzzSwapRouter.swap, (address(precisionX), address(precisionA), inA, mins[0]))
    });
    swaps[1] = SharedVaultGateway.SwapParams({
      tokenIn: address(precisionX),
      amountIn: inB,
      tokenOut: address(precisionB),
      amountOutMin: outB,
      swapData: abi.encodeCall(FuzzSwapRouter.swap, (address(precisionX), address(precisionB), inB, outB))
    });

    SharedVaultGateway.SwapAndDepositParams memory params = SharedVaultGateway.SwapAndDepositParams({
      vault: ISharedVault(address(precisionVault)),
      inputs: _gatewayInputs1(address(precisionX), inA + inB),
      swaps: swaps,
      minDepositAmounts: mins,
      slippageBps: 0,
      minShares: 0,
      sweepTokens: new address[](0)
    });

    if (belowFloor) {
      try gateway.swapAndDeposit(params) returns (uint256) {
        assert(false);
      } catch { }
      return;
    }

    uint256 sharesBefore = precisionVault.balanceOf(address(this));
    uint256 vaultBBefore = precisionB.balanceOf(address(precisionVault));
    try gateway.swapAndDeposit(params) returns (uint256 shares) {
      assert(shares > 0);
      assert(precisionVault.balanceOf(address(this)) == sharesBefore + shares);
      assert(precisionB.balanceOf(address(precisionVault)) == vaultBBefore + mins[1]);
      assert(precisionX.balanceOf(address(gateway)) == 0);
    } catch {
      assert(false);
    }

    _assertPrecisionShareConservation();
    _assertPositiveBacking(precisionVault);
  }

  function gateway_withdraw_forwards_below_floor() external {
    precisionConfigManager.setMinTokenPrecision(5);
    uint256[4] memory mins = precisionVault.getMinDepositAmounts();
    if (mins[1] <= 1) return;

    uint256 shares = _belowFloorWithdrawShares(precisionVault, mins[1]);
    if (shares == 0 || shares > precisionVault.balanceOf(address(this))) return;

    uint256[4] memory preview = precisionVault.previewWithdraw(shares);
    if (preview[1] == 0 || preview[1] >= mins[1]) return;

    uint256 bBefore = precisionB.balanceOf(address(this));
    SharedVaultGateway.WithdrawAndSwapParams memory params = SharedVaultGateway.WithdrawAndSwapParams({
      vault: ISharedVault(address(precisionVault)),
      shares: shares,
      minWithdrawAmounts: [uint256(0), uint256(0), uint256(0), uint256(0)],
      unwrapOnWithdraw: false,
      swaps: new SharedVaultGateway.SwapParams[](0),
      sweepTokens: new address[](0)
    });

    try gateway.withdrawAndSwap(params) returns (uint256[4] memory got) {
      assert(got[1] == preview[1]);
      assert(got[1] < mins[1]);
      assert(precisionB.balanceOf(address(this)) == bBefore + got[1]);
      assert(precisionA.balanceOf(address(gateway)) == 0);
      assert(precisionB.balanceOf(address(gateway)) == 0);
      assert(precisionVault.balanceOf(address(gateway)) == 0);
    } catch {
      assert(false);
    }

    _assertPrecisionShareConservation();
    _assertPositiveBacking(precisionVault);
  }

  // -------------------------------------------------------------------------
  // Stateful fee-bearing vault (platform 10% + owner 5% on collected rewards)
  // -------------------------------------------------------------------------

  /// @dev Accrue extra rewards on the fee vault's LP position. setRewards REPLACES the staged
  ///      rewards, so re-read the live pending amount and add on top.
  function fee_accrue_rewards(uint256 reward0, uint256 reward1) external {
    reward0 = _bound(reward0, 0, 1e24);
    reward1 = _bound(reward1, 0, 1e24);
    if (reward0 == 0 && reward1 == 0) return;

    (uint256 total0, uint256 total1) = feePool.getAmounts(address(feeNfpm), FEE_TOKEN_ID);
    (uint256 principal0, uint256 principal1) = feePool.getPrincipal(address(feeNfpm), FEE_TOKEN_ID);

    feeA.mint(address(feePool), reward0);
    feeB.mint(address(feePool), reward1);
    feePool.setRewards(address(feeNfpm), FEE_TOKEN_ID, (total0 - principal0) + reward0, (total1 - principal1) + reward1);

    _assertPositiveBacking(feeVault);
  }

  function fee_deposit(uint256 amountA) external {
    amountA = _bound(amountA, 1e13, MAX_18);
    uint256[4] memory totals = feeVault.getTotalBalances();
    if (totals[0] == 0 || totals[1] == 0) return;

    uint256[4] memory amounts;
    amounts[0] = amountA;
    amounts[1] = _ceilMulDiv(amountA, totals[1], totals[0]);
    if (amounts[1] > MAX_18) return;

    uint256 preview = feeVault.previewDeposit(amounts);
    uint256 supplyBefore = feeVault.totalSupply();
    uint256 posBefore = feeVault.getPositionCount();
    (uint256 principal0Before, uint256 principal1Before) = feePool.getPrincipal(address(feeNfpm), FEE_TOKEN_ID);

    try feePlayer.deposit(amounts, 100) returns (uint256 shares) {
      assert(preview > 0);
      assert(shares > 0);
      assert(feeVault.totalSupply() == supplyBefore + shares);
      assert(feeVault.getPositionCount() == posBefore);
      (uint256 principal0After, uint256 principal1After) = feePool.getPrincipal(address(feeNfpm), FEE_TOKEN_ID);
      assert(principal0After >= principal0Before);
      assert(principal1After >= principal1Before);
    } catch {
      assert(preview == 0);
    }

    _assertFeeShareConservation();
    _assertPositiveBacking(feeVault);
  }

  /// @dev The core fee-vault property: previewWithdraw (which nets platform + owner fees off the
  ///      uncollected rewards via SharedVaultPreviewLib) must match the realized withdraw — which
  ///      actually collects the rewards, pays the fee recipients, and distributes the net — within
  ///      1 wei per token (the documented floor-splitting drift). A divergence means the preview
  ///      fee math no longer mirrors the collect-path fee math.
  function fee_withdraw(uint256 shareSeed) external {
    uint256 bal = feeVault.balanceOf(address(feePlayer));
    if (bal == 0) return;

    uint256 shares = _sharesFromSeed(bal, shareSeed);
    uint256[4] memory preview = feeVault.previewWithdraw(shares);
    if (!_hasNonDustOutput(preview)) return;
    uint256 supplyBefore = feeVault.totalSupply();
    uint256 platformABefore = feeA.balanceOf(FEE_PLATFORM_RECIPIENT);
    uint256 platformBBefore = feeB.balanceOf(FEE_PLATFORM_RECIPIENT);
    uint256 ownerABefore = feeA.balanceOf(FEE_VAULT_OWNER);
    uint256 ownerBBefore = feeB.balanceOf(FEE_VAULT_OWNER);
    uint256[4] memory mins;

    try feePlayer.withdraw(shares, mins, false) returns (uint256[4] memory got) {
      assert(_hasAnyOutput(got));
      assert(_withinOneUnit(got[0], preview[0]));
      assert(_withinOneUnit(got[1], preview[1]));
      assert(feeVault.totalSupply() == supplyBefore - shares);
      // Fee recipients never lose balance on a withdraw.
      assert(feeA.balanceOf(FEE_PLATFORM_RECIPIENT) >= platformABefore);
      assert(feeB.balanceOf(FEE_PLATFORM_RECIPIENT) >= platformBBefore);
      assert(feeA.balanceOf(FEE_VAULT_OWNER) >= ownerABefore);
      assert(feeB.balanceOf(FEE_VAULT_OWNER) >= ownerBBefore);
    } catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
    }

    _assertFeeShareConservation();
    _assertPositiveBacking(feeVault);
  }

  // -------------------------------------------------------------------------
  // Roundtrip no-profit invariant
  // -------------------------------------------------------------------------

  /// @dev No value extraction: an immediate deposit -> withdraw(all minted shares) roundtrip must
  ///      never leave the player with MORE of any vault token than they started with. Rounding in
  ///      both the deposit pull (ceil + precision floor) and the withdraw split (floor) favors the
  ///      vault, so the player's balances can only stay equal or shrink. The fork harness pins this
  ///      against real pools; this is the mock-side twin that runs orders of magnitude more sequences.
  function idle_roundtrip_no_profit(uint8 idx, uint256 amountA, uint256 amountB) external {
    idx = idx % 3;
    amountA = _bound(amountA, 1e13, MAX_18);
    amountB = _bound(amountB, 1e13, MAX_18 * 2);
    SharedFuzzPlayer player = idlePlayers[idx];

    uint256 balABefore = idleA.balanceOf(address(player));
    uint256 balBBefore = idleB.balanceOf(address(player));
    uint256 sharesBefore = idleVault.balanceOf(address(player));

    uint256[4] memory amounts = [amountA, amountB, uint256(0), uint256(0)];
    uint256 minted;
    try player.deposit(amounts, 0) returns (uint256 shares) {
      minted = shares;
    } catch {
      return; // invalid-ratio deposits are covered by idle_deposit's preview assertions
    }
    if (minted == 0) return;

    uint256[4] memory mins;
    try player.withdraw(minted, mins, false) returns (uint256[4] memory) { }
    catch (bytes memory reason) {
      assert(_isAcceptablePreviewedWithdrawRevert(reason));
      return;
    }

    assert(idleVault.balanceOf(address(player)) == sharesBefore);
    assert(idleA.balanceOf(address(player)) <= balABefore);
    assert(idleB.balanceOf(address(player)) <= balBBefore);

    _assertIdleShareConservation();
    _assertPositiveBacking(idleVault);
  }

  // Assertion-mode standalone checks. These are deliberately assert-based
  // instead of echidna_* bool properties because config.yaml uses assertion mode.
  function assert_idle_share_conservation() public view {
    _assertIdleShareConservation();
  }

  function assert_fee_share_conservation() public view {
    _assertFeeShareConservation();
  }

  function assert_multi_share_conservation() public view {
    _assertMultiShareConservation();
  }

  function assert_lp_share_conservation() public view {
    _assertLpShareConservation();
  }

  function assert_precision_share_conservation() public view {
    _assertPrecisionShareConservation();
  }

  function assert_all_backed_when_supply_exists() public view {
    _assertPositiveBacking(idleVault);
    _assertPositiveBacking(multiVault);
    _assertPositiveBacking(lpVault);
    _assertPositiveBacking(wethVault);
    _assertPositiveBacking(precisionVault);
    _assertPositiveBacking(feeVault);
  }

  // -------------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------------

  function _setupIdleVault() internal {
    idleA = new FuzzERC20("IdleA", "IDA", 18);
    idleB = new FuzzERC20("IdleB", "IDB", 18);
    idleVault = new SharedVault();

    idleA.mint(address(idleVault), 1000e18);
    idleB.mint(address(idleVault), 2000e18);
    address[4] memory toks = [address(idleA), address(idleB), address(0), address(0)];
    uint256[4] memory init = [uint256(1000e18), uint256(2000e18), uint256(0), uint256(0)];
    idleVault.initialize("IdleShared", toks, init, address(this), address(this), address(configManager), address(0), 0);

    for (uint256 i; i < 3; i++) {
      idlePlayers[i] = new SharedFuzzPlayer(idleVault, toks);
      idleA.mint(address(idlePlayers[i]), 1e30);
      idleB.mint(address(idlePlayers[i]), 2e30);
    }
  }

  function _setupMultiVault() internal {
    multiA = new FuzzERC20("MultiA", "MUA", 18);
    multiB = new FuzzERC20("MultiB", "MUB", 18);
    multiC = new FuzzERC20("MultiC", "MUC", 6);
    multiD = new FuzzERC20("MultiD", "MUD", 8);
    multiVault = new SharedVault();

    multiA.mint(address(multiVault), 100e18);
    multiB.mint(address(multiVault), 200e18);
    multiC.mint(address(multiVault), 100e6);
    multiD.mint(address(multiVault), 2e8);
    address[4] memory toks = [address(multiA), address(multiB), address(multiC), address(multiD)];
    uint256[4] memory init = [uint256(100e18), uint256(200e18), uint256(100e6), uint256(2e8)];
    multiVault.initialize(
      "MultiShared", toks, init, address(this), address(this), address(configManager), address(0), 0
    );

    for (uint256 i; i < 2; i++) {
      multiPlayers[i] = new SharedFuzzPlayer(multiVault, toks);
      multiA.mint(address(multiPlayers[i]), 1e30);
      multiB.mint(address(multiPlayers[i]), 2e30);
      multiC.mint(address(multiPlayers[i]), 1e18);
      multiD.mint(address(multiPlayers[i]), 1e18);
    }
  }

  function _setupLpVault() internal {
    lpA = new FuzzERC20("LpA", "LPA", 18);
    lpB = new FuzzERC20("LpB", "LPB", 18);
    lpPool = new FuzzLpPool();
    lpNfpm = new FuzzERC721();

    address[] memory targets = new address[](0);
    address[] memory nfpms = new address[](0);
    SharedConfigManager cm = _newConfig(targets, nfpms);

    lpStrategy = new FuzzLpStrategy(lpPool, address(lpNfpm), 1, address(lpA), address(lpB));
    _whitelist(cm, address(lpStrategy), address(lpNfpm));

    lpVault = new SharedVault();
    lpA.mint(address(lpVault), 100e18);
    lpB.mint(address(lpVault), 100e18);
    address[4] memory toks = [address(lpA), address(lpB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    lpVault.initialize("LpShared", toks, init, address(this), address(this), address(cm), address(0), 0);

    // Two tracked positions so deposits/withdraws iterate the positions array (including the
    // swap-with-last removal reload in SharedVault._withdraw) instead of a single-entry loop.
    lpStrategy2 = new FuzzLpStrategy(lpPool, address(lpNfpm), 2, address(lpA), address(lpB));
    _whitelist(cm, address(lpStrategy2), address(lpNfpm));

    lpNfpm.mint(address(lpVault), 1);
    lpNfpm.mint(address(lpVault), 2);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](2);
    actions[0] = ISharedVault.Action({
      target: address(lpStrategy),
      data: abi.encode(uint256(50e18), uint256(50e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    actions[1] = ISharedVault.Action({
      target: address(lpStrategy2),
      data: abi.encode(uint256(20e18), uint256(10e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    lpVault.execute(actions);

    lpA.mint(address(lpPool), 10e18);
    lpB.mint(address(lpPool), 20e18);
    lpPool.setRewards(address(lpNfpm), 1, 10e18, 20e18);

    lpPlayer = new SharedFuzzPlayer(lpVault, toks);
    lpA.mint(address(lpPlayer), 1e30);
    lpB.mint(address(lpPlayer), 1e30);
  }

  function _setupWethVault() internal {
    wethTokenA = new FuzzERC20("WethPairA", "WPA", 18);
    weth = new FuzzWETH9();
    wethVault = new SharedVault();

    wethTokenA.mint(address(wethVault), 100e18);
    weth.mint(address(wethVault), 100 ether);

    address[4] memory toks = [address(wethTokenA), address(weth), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100 ether), uint256(0), uint256(0)];
    wethVault.initialize(
      "WethShared", toks, init, address(this), address(this), address(configManager), address(weth), 0
    );

    wethPlayer = new SharedFuzzPlayer(wethVault, toks);
    wethTokenA.mint(address(wethPlayer), 1e30);
  }

  function _setupPrecisionGatewayVault() internal {
    precisionConfigManager = _newConfig(new address[](0), new address[](0));
    precisionVault = new SharedVault();
    precisionA = new FuzzERC20("PrecisionA", "PRA", 18);
    precisionB = new FuzzERC20("PrecisionB", "PRB", 8);
    precisionX = new FuzzERC20("PrecisionX", "PRX", 18);
    gateway = new SharedVaultGateway();
    gateway.initialize(address(this), address(swapRouter), address(weth));

    precisionA.mint(address(precisionVault), 100e18);
    precisionB.mint(address(precisionVault), 5521);
    address[4] memory toks = [address(precisionA), address(precisionB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(5521), uint256(0), uint256(0)];
    precisionVault.initialize(
      "PrecisionShared", toks, init, address(this), address(this), address(precisionConfigManager), address(0), 0
    );

    precisionA.approve(address(precisionVault), type(uint256).max);
    precisionB.approve(address(precisionVault), type(uint256).max);
    precisionA.approve(address(gateway), type(uint256).max);
    precisionB.approve(address(gateway), type(uint256).max);
    precisionX.approve(address(gateway), type(uint256).max);
    precisionVault.approve(address(gateway), type(uint256).max);
  }

  function _setupFeeVault() internal {
    feeA = new FuzzERC20("FeeA", "FEA", 18);
    feeB = new FuzzERC20("FeeB", "FEB", 18);
    feePool = new FuzzLpPool();
    feeNfpm = new FuzzERC721();

    // Platform fee 10% with a dedicated recipient; address(this) is a whitelisted caller so it
    // can drive execute() even though the vault owner is the passive FEE_VAULT_OWNER address.
    feeConfigManager = new SharedConfigManager();
    address[] memory empty = new address[](0);
    address[] memory callers = new address[](1);
    callers[0] = address(this);
    feeConfigManager.initialize(address(this), empty, callers, FEE_PLATFORM_RECIPIENT, 1000, empty, empty, empty);

    feeStrategy = new FuzzLpStrategy(feePool, address(feeNfpm), FEE_TOKEN_ID, address(feeA), address(feeB));
    _whitelist(feeConfigManager, address(feeStrategy), address(feeNfpm));

    feeVault = new SharedVault();
    feeA.mint(address(feeVault), 100e18);
    feeB.mint(address(feeVault), 100e18);
    address[4] memory toks = [address(feeA), address(feeB), address(0), address(0)];
    uint256[4] memory init = [uint256(100e18), uint256(100e18), uint256(0), uint256(0)];
    // Vault-owner fee 5% on top of the 10% platform fee.
    feeVault.initialize(
      "FeeShared", toks, init, FEE_VAULT_OWNER, address(this), address(feeConfigManager), address(0), 500
    );

    feeNfpm.mint(address(feeVault), FEE_TOKEN_ID);
    ISharedVault.Action[] memory actions = new ISharedVault.Action[](1);
    actions[0] = ISharedVault.Action({
      target: address(feeStrategy),
      data: abi.encode(uint256(50e18), uint256(50e18)),
      callType: ISharedCommon.CallType.DELEGATECALL
    });
    feeVault.execute(actions);

    // Seed initial rewards so fee paths are live from the first sequence.
    feeA.mint(address(feePool), 10e18);
    feeB.mint(address(feePool), 20e18);
    feePool.setRewards(address(feeNfpm), FEE_TOKEN_ID, 10e18, 20e18);

    feePlayer = new SharedFuzzPlayer(feeVault, toks);
    feeA.mint(address(feePlayer), 1e30);
    feeB.mint(address(feePlayer), 1e30);
  }

  function _newConfig(address[] memory targets, address[] memory nfpms) internal returns (SharedConfigManager cm) {
    cm = new SharedConfigManager();
    address[] memory empty = new address[](0);
    cm.initialize(address(this), targets, empty, address(this), 0, nfpms, empty, empty);
    _whitelistSigner(cm);
  }

  function _whitelist(SharedConfigManager cm, address target, address nfpm) internal {
    address[] memory targets = new address[](1);
    targets[0] = target;
    cm.setWhitelistTargets(targets, true);
    address[] memory nfpms = new address[](1);
    nfpms[0] = nfpm;
    cm.setWhitelistNfpms(nfpms, true);
  }

  function _whitelistSwapRouter(SharedConfigManager cm, address router) internal {
    address[] memory routers = new address[](1);
    routers[0] = router;
    cm.setWhitelistSwapRouters(routers, true);
  }

  function _whitelistSigner(SharedConfigManager cm) internal {
    address[] memory signers = new address[](1);
    signers[0] = address(swapDataSigner);
    cm.setWhitelistSigners(signers, true);
  }

  function _signedSwapData(
    SharedVault targetVault,
    address router,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    bytes memory rawSwapData
  ) internal returns (bytes memory) {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 nonce = bytes32(++swapDataNonce);
    bytes32 digest = SharedSwapDataSignature.hash(
      address(targetVault),
      address(swapDataSigner),
      router,
      tokenIn,
      tokenOut,
      amountIn,
      amountOutMin,
      rawSwapData,
      deadline,
      nonce
    );
    return abi.encode(rawSwapData, address(targetVault), deadline, address(swapDataSigner), nonce, abi.encode(digest));
  }

  // -------------------------------------------------------------------------
  // Invariant helpers
  // -------------------------------------------------------------------------

  function _assertIdleShareConservation() internal view {
    uint256 sum = idleVault.balanceOf(address(this));
    for (uint256 i; i < 3; i++) {
      sum += idleVault.balanceOf(address(idlePlayers[i]));
    }
    assert(sum == idleVault.totalSupply());
  }

  function _assertMultiShareConservation() internal view {
    uint256 sum = multiVault.balanceOf(address(this));
    for (uint256 i; i < 2; i++) {
      sum += multiVault.balanceOf(address(multiPlayers[i]));
    }
    assert(sum == multiVault.totalSupply());
  }

  function _assertLpShareConservation() internal view {
    uint256 sum = lpVault.balanceOf(address(this)) + lpVault.balanceOf(address(lpPlayer));
    assert(sum == lpVault.totalSupply());
  }

  function _assertPrecisionShareConservation() internal view {
    assert(precisionVault.balanceOf(address(this)) == precisionVault.totalSupply());
  }

  function _assertFeeShareConservation() internal view {
    uint256 sum = feeVault.balanceOf(address(this)) + feeVault.balanceOf(address(feePlayer))
      + feeVault.balanceOf(FEE_VAULT_OWNER);
    assert(sum == feeVault.totalSupply());
  }

  function _assertPositiveBacking(SharedVault v) internal view {
    if (v.totalSupply() == 0) return;
    uint256[4] memory totals = v.getTotalBalances();
    assert(totals[0] > 0 || totals[1] > 0 || totals[2] > 0 || totals[3] > 0);
  }

  function _sharesFromSeed(uint256 balance, uint256 seed) internal pure returns (uint256 shares) {
    if (balance == 0) return 0;
    if (seed % 5 == 0) return balance;
    shares = seed % balance;
    if (shares == 0) shares = 1;
  }

  function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  function _feeAmount(uint256 amount, uint16 bps) internal pure returns (uint256) {
    return (amount / 10_000) * bps + ((amount % 10_000) * bps) / 10_000;
  }

  function _ceilMulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
    if (x == 0 || y == 0) return 0;
    return ((x * y) - 1) / d + 1;
  }

  function _hasAnyOutput(uint256[4] memory amounts) internal pure returns (bool) {
    return amounts[0] > 0 || amounts[1] > 0 || amounts[2] > 0 || amounts[3] > 0;
  }

  function _hasNonDustOutput(uint256[4] memory amounts) internal pure returns (bool) {
    return amounts[0] > 1 || amounts[1] > 1 || amounts[2] > 1 || amounts[3] > 1;
  }

  function _belowFloorWithdrawShares(SharedVault v, uint256 floor) internal view returns (uint256 shares) {
    uint256[4] memory totals = v.getTotalBalances();
    uint256 supply = v.totalSupply();
    if (supply == 0 || totals[1] == 0 || floor <= 1) return 0;
    shares = (supply * (floor - 1)) / totals[1];
    if (shares == 0) return 0;
    if (shares >= supply) shares = supply - 1;
  }

  function _gatewayInputs1(address token0, uint256 amount0)
    internal
    pure
    returns (SharedVaultGateway.InputToken[] memory inputs)
  {
    inputs = new SharedVaultGateway.InputToken[](1);
    inputs[0] = SharedVaultGateway.InputToken({ token: token0, amount: amount0 });
  }

  function _gatewayInputs2(address token0, uint256 amount0, address token1, uint256 amount1)
    internal
    pure
    returns (SharedVaultGateway.InputToken[] memory inputs)
  {
    inputs = new SharedVaultGateway.InputToken[](2);
    inputs[0] = SharedVaultGateway.InputToken({ token: token0, amount: amount0 });
    inputs[1] = SharedVaultGateway.InputToken({ token: token1, amount: amount1 });
  }

  function _withinOneUnit(uint256 actual, uint256 expected) internal pure returns (bool) {
    return actual >= expected ? actual - expected <= 1 : expected - actual <= 1;
  }

  /// @dev Preview divides once over (idle + ΣLP) while withdraw floors the idle slice and each
  ///      position's exit separately, so the realized amount can fall short of preview by up to one
  ///      wei per floor — i.e. the tracked position count (W-7 upper-bound semantics).
  function _withinUnits(uint256 actual, uint256 expected, uint256 tolerance) internal pure returns (bool) {
    return actual >= expected ? actual - expected <= tolerance : expected - actual <= tolerance;
  }

  /// @dev In these closed mock states, non-dust previews are expected to withdraw.
  ///      This filter only tolerates the strategy/NFPM allowlist failures that a
  ///      future stateful action could trigger between preview and execution.
  function _isAcceptablePreviewedWithdrawRevert(bytes memory reason) internal pure returns (bool) {
    bytes4 selector = _revertSelector(reason);
    return selector == ISharedCommon.StrategyCallFailed.selector || selector == ISharedCommon.InvalidNfpm.selector;
  }

  function _revertSelector(bytes memory reason) internal pure returns (bytes4 selector) {
    if (reason.length < 4) return bytes4(0);
    assembly {
      selector := mload(add(reason, 32))
    }
  }
}
