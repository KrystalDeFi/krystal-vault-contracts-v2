// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { PrivateVault } from "../../contracts/private-vault/core/PrivateVault.sol";
import { PrivateConfigManager } from "../../contracts/private-vault/core/PrivateConfigManager.sol";
import { IPrivateCommon } from "../../contracts/private-vault/interfaces/core/IPrivateCommon.sol";
import { AerodromeFarmingStrategy } from "../../contracts/private-vault/strategies/farm/AerodromeFarmingStrategy.sol";
import { IAeroCLGauge } from "../../contracts/common/interfaces/protocols/aerodrome/IAeroCLGauge.sol";

contract MockRewardToken is ERC20 {
  constructor(string memory symbol) ERC20(symbol, symbol) { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/// @dev Slipstream-shaped NFPM: 12-field `positions`, `factory()`, enumerable.
contract MockCLNfpm is ERC721Enumerable {
  struct Pos {
    address token0;
    address token1;
    int24 tickSpacing;
  }

  address public factory;
  mapping(uint256 => Pos) internal _pos;

  constructor(address _factory) ERC721("Mock CL Position", "MCL") {
    factory = _factory;
  }

  function mintPosition(address to, uint256 tokenId, address token0, address token1, int24 tickSpacing) external {
    _pos[tokenId] = Pos(token0, token1, tickSpacing);
    _mint(to, tokenId);
  }

  function positions(uint256 tokenId)
    external
    view
    returns (uint96, address, address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    Pos memory p = _pos[tokenId];
    require(p.token0 != address(0), "Invalid token ID");
    return (0, address(0), p.token0, p.token1, p.tickSpacing, -100, 100, 1e18, 0, 0, 0, 0);
  }
}

contract MockCLFactory {
  mapping(address => mapping(address => mapping(int24 => address))) public getPool;

  function setPool(address token0, address token1, int24 tickSpacing, address pool) external {
    getPool[token0][token1][tickSpacing] = pool;
    getPool[token1][token0][tickSpacing] = pool;
  }
}

contract MockCLPool {
  address public gauge;

  function setGauge(address _gauge) external {
    gauge = _gauge;
  }
}

contract MockLegacyGaugeFactory {
  address public nft;

  constructor(address _nft) {
    nft = _nft;
  }
}

contract MockAeroGaugeFactory {
  address public nft;
  address public leafVoter;
  mapping(address => uint128) public emissionCap;

  constructor(address _nft, address _leafVoter) {
    nft = _nft;
    leafVoter = _leafVoter;
  }

  function setEmissionCap(address gauge, uint128 cap) external {
    emissionCap[gauge] = cap;
  }
}

/// @dev Leaf-chain emissions handler: pays the receipt token.
contract MockLeafEmissionsHandler {
  address public RECEIPT_TOKEN;

  constructor(address receiptToken) {
    RECEIPT_TOKEN = receiptToken;
  }
}

/// @dev Base's root emissions handler: redeems the receipt token for AERO, has no `RECEIPT_TOKEN()`.
contract MockRootEmissionsHandler { }

contract MockLeafVoter {
  address public RECEIPT_TOKEN;
  address public EMISSIONS_HANDLER;
  address public ORCHESTRATOR;
  mapping(address => bool) public isActivated;

  constructor(address receiptToken, address handler) {
    RECEIPT_TOKEN = receiptToken;
    EMISSIONS_HANDLER = handler;
  }

  function setActivated(address gauge, bool activated) external {
    isActivated[gauge] = activated;
  }

  function setOrchestrator(address orchestrator) external {
    ORCHESTRATOR = orchestrator;
  }
}

/// @dev Base's redeem route, LeafVoter → message orchestrator → root-local adapter → root orchestrator → Voter.
contract MockMessageOrchestrator {
  address public adapter;

  constructor(address _adapter) {
    adapter = _adapter;
  }
}

contract MockRootLocalAdapter {
  address public ROOT_MESSAGE_ORCHESTRATOR;

  constructor(address rootOrchestrator) {
    ROOT_MESSAGE_ORCHESTRATOR = rootOrchestrator;
  }
}

contract MockRootMessageOrchestrator {
  address public VOTER;

  constructor(address voter) {
    VOTER = voter;
  }
}

contract MockVoter {
  address public TOKEN;

  constructor(address token) {
    TOKEN = token;
  }
}

/// @dev Legacy Aerodrome CLGauge: `rewardToken()`, `getReward(tokenId)`, and `withdraw` pays pending rewards too.
contract MockLegacyCLGauge is ERC721Holder {
  IERC721 public immutable nft;
  MockRewardToken public immutable rewardToken;
  mapping(uint256 => address) public stakerOf;
  mapping(uint256 => uint256) public pending;

  constructor(address _nft, MockRewardToken _rewardToken) {
    nft = IERC721(_nft);
    rewardToken = _rewardToken;
  }

  function setPending(uint256 tokenId, uint256 amount) external {
    pending[tokenId] = amount;
  }

  function deposit(uint256 tokenId) external {
    nft.safeTransferFrom(msg.sender, address(this), tokenId);
    stakerOf[tokenId] = msg.sender;
  }

  function getReward(uint256 tokenId) external {
    require(stakerOf[tokenId] == msg.sender, "NA");
    _pay(tokenId, msg.sender);
  }

  function withdraw(uint256 tokenId) external {
    require(stakerOf[tokenId] == msg.sender, "NA");
    _pay(tokenId, msg.sender);
    delete stakerOf[tokenId];
    nft.safeTransferFrom(address(this), msg.sender, tokenId);
  }

  function _pay(uint256 tokenId, address to) internal {
    uint256 amount = pending[tokenId];
    if (amount == 0) return;
    pending[tokenId] = 0;
    rewardToken.mint(to, amount);
  }
}

/// @dev Aero (MetaDEX) CLGauge semantics: no `rewardToken`/`getReward`; `claimEmissions` pays the listed positions
///      plus the account's deferred emissions and reverts when the mint fails; `withdraw` defers on a failed mint.
contract MockAeroCLGauge is ERC721Holder {
  IERC721 public immutable nft;
  MockRewardToken public immutable emission;
  bool public mintReverts;
  uint256 public claimCalls;
  mapping(uint256 => address) internal _stakerOf;
  mapping(uint256 => uint256) public pending;
  mapping(address => uint256) public deferredEmissions;

  constructor(address _nft, MockRewardToken _emission) {
    nft = IERC721(_nft);
    emission = _emission;
  }

  function setPending(uint256 tokenId, uint256 amount) external {
    pending[tokenId] = amount;
  }

  function setMintReverts(bool reverts) external {
    mintReverts = reverts;
  }

  /// @dev Stands in for the gauge factory's `emergencyWithdrawEnabled()` switch.
  bool public emergencyEnabled;

  function setEmergencyEnabled(bool enabled) external {
    emergencyEnabled = enabled;
  }

  function emergencyWithdraw(uint256 tokenId) external {
    require(emergencyEnabled, "NE");
    require(_stakerOf[tokenId] == msg.sender, "NA");
    delete _stakerOf[tokenId];
    pending[tokenId] = 0; // forfeited
    nft.safeTransferFrom(address(this), msg.sender, tokenId);
  }

  function deposit(uint256 tokenId) external {
    nft.safeTransferFrom(msg.sender, address(this), tokenId);
    _stakerOf[tokenId] = msg.sender;
  }

  function withdraw(uint256 tokenId) external {
    require(_stakerOf[tokenId] == msg.sender, "NA");
    delete _stakerOf[tokenId];
    uint256 amount = pending[tokenId];
    pending[tokenId] = 0;
    if (amount > 0) {
      if (mintReverts) deferredEmissions[msg.sender] += amount;
      else emission.mint(msg.sender, amount);
    }
    nft.safeTransferFrom(address(this), msg.sender, tokenId);
  }

  function claimEmissions(address account, address recipient, uint256[] calldata tokenIds) external {
    require(msg.sender == account, "NA");
    claimCalls++;
    require(tokenIds.length > 0 || deferredEmissions[account] > 0, "NS");
    uint256 total = deferredEmissions[account];
    deferredEmissions[account] = 0;
    for (uint256 i; i < tokenIds.length; i++) {
      require(_stakerOf[tokenIds[i]] == account, "NA");
      total += pending[tokenIds[i]];
      pending[tokenIds[i]] = 0;
    }
    require(!mintReverts, "CeilingExceeded");
    if (total > 0) emission.mint(recipient, total);
  }

  function stakedContains(address account, uint256 tokenId) external view returns (bool) {
    return _stakerOf[tokenId] == account;
  }
}

contract AerodromeFarmingStrategyTest is Test {
  uint256 internal constant Q64 = 0x10000000000000000;
  address internal constant OWNER = address(0xA11CE);
  address internal constant OPERATOR = address(0x0FE7A70);
  address internal constant TOKEN0 = address(0x1000);
  address internal constant TOKEN1 = address(0x2000);
  int24 internal constant TICK_SPACING = 100;
  uint256 internal constant REWARD = 100e18;

  address internal feeRecipient = makeAddr("feeRecipient");
  uint64 internal rewardFeeX64 = uint64(Q64 * 5 / 100);
  uint64 internal gasFeeX64 = uint64(Q64 / 100);

  PrivateConfigManager internal configManager;
  PrivateVault internal vault;

  MockRewardToken internal legacyReward;
  MockCLNfpm internal legacyNfpm;
  MockLegacyCLGauge internal legacyGauge;
  MockLegacyGaugeFactory internal legacyGaugeFactory;
  AerodromeFarmingStrategy internal legacyStrategy;

  MockRewardToken internal xAero;
  MockCLNfpm internal aeroNfpm;
  MockAeroCLGauge internal aeroGauge;
  MockLeafVoter internal leafVoter;
  MockAeroGaugeFactory internal aeroGaugeFactory;
  AerodromeFarmingStrategy internal aeroStrategy;

  function setUp() public {
    address[] memory callers = new address[](1);
    callers[0] = OPERATOR;
    configManager = new PrivateConfigManager();
    configManager.initialize(address(this), new address[](0), callers, feeRecipient);

    vault = new PrivateVault();
    vault.initialize(OWNER, address(configManager), "farm");

    legacyReward = new MockRewardToken("AERO");
    MockCLFactory legacyFactory = new MockCLFactory();
    legacyNfpm = new MockCLNfpm(address(legacyFactory));
    legacyGauge = new MockLegacyCLGauge(address(legacyNfpm), legacyReward);
    _wirePool(legacyFactory, address(legacyGauge));
    legacyGaugeFactory = new MockLegacyGaugeFactory(address(legacyNfpm));
    legacyStrategy = new AerodromeFarmingStrategy(address(legacyGaugeFactory), address(configManager), address(0));

    xAero = new MockRewardToken("xAERO");
    MockCLFactory aeroFactory = new MockCLFactory();
    aeroNfpm = new MockCLNfpm(address(aeroFactory));
    aeroGauge = new MockAeroCLGauge(address(aeroNfpm), xAero);
    _wirePool(aeroFactory, address(aeroGauge));
    // A leaf chain: the LeafVoter pays its receipt token (xAERO) through a handler that transfers it
    leafVoter = new MockLeafVoter(address(xAero), address(new MockLeafEmissionsHandler(address(xAero))));
    leafVoter.setActivated(address(aeroGauge), true);
    aeroGaugeFactory = new MockAeroGaugeFactory(address(aeroNfpm), address(leafVoter));
    aeroGaugeFactory.setEmissionCap(address(aeroGauge), 1e18);
    aeroStrategy = new AerodromeFarmingStrategy(address(aeroGaugeFactory), address(configManager), address(xAero));

    address[] memory targets = new address[](2);
    targets[0] = address(legacyStrategy);
    targets[1] = address(aeroStrategy);
    configManager.setWhitelistTargets(targets, true);
  }

  function _wirePool(MockCLFactory factory, address gauge) internal {
    MockCLPool pool = new MockCLPool();
    pool.setGauge(gauge);
    factory.setPool(TOKEN0, TOKEN1, TICK_SPACING, address(pool));
  }

  function _exec(address strategy, bytes memory data) internal {
    address[] memory targets = new address[](1);
    targets[0] = strategy;
    bytes[] memory calls = new bytes[](1);
    calls[0] = data;
    IPrivateCommon.CallType[] memory callTypes = new IPrivateCommon.CallType[](1);
    callTypes[0] = IPrivateCommon.CallType.DELEGATECALL;
    vm.prank(OPERATOR);
    vault.multicall(targets, new uint256[](1), calls, callTypes);
  }

  function _stake(AerodromeFarmingStrategy strategy, MockCLNfpm nfpm, uint256 tokenId) internal {
    nfpm.mintPosition(address(vault), tokenId, TOKEN0, TOKEN1, TICK_SPACING);
    _exec(address(strategy), abi.encodeCall(AerodromeFarmingStrategy.deposit, (tokenId)));
  }

  function _harvest(AerodromeFarmingStrategy strategy, uint256 tokenId, bool toOwner) internal {
    _exec(
      address(strategy), abi.encodeCall(AerodromeFarmingStrategy.harvest, (tokenId, rewardFeeX64, gasFeeX64, toOwner))
    );
  }

  function _withdraw(AerodromeFarmingStrategy strategy, uint256 tokenId, bool toOwner) internal {
    _exec(
      address(strategy), abi.encodeCall(AerodromeFarmingStrategy.withdraw, (tokenId, rewardFeeX64, gasFeeX64, toOwner))
    );
  }

  function _fee(uint256 amount) internal view returns (uint256) {
    return Math.mulDiv(amount, rewardFeeX64, Q64) + Math.mulDiv(amount, gasFeeX64, Q64);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Constructor: gauge factory family and emission token
  // ---------------------------------------------------------------------------------------------------------------

  function test_constructor_bindsFactoryNfpmLeafVoterAndEmissionToken() public view {
    assertEq(legacyStrategy.leafVoter(), address(0));
    assertEq(legacyStrategy.emissionToken(), address(0));
    assertEq(legacyStrategy.nfpm(), address(legacyNfpm));
    assertEq(aeroStrategy.leafVoter(), address(leafVoter));
    assertEq(aeroStrategy.emissionToken(), address(xAero));
    assertEq(aeroStrategy.nfpm(), address(aeroNfpm));
    assertEq(aeroStrategy.gaugeFactory(), address(aeroGaugeFactory));
  }

  function test_constructor_revertsWhen_aeroFactoryGetsNoEmissionToken() public {
    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(address(aeroGaugeFactory), address(configManager), address(0));
  }

  /// A leaf chain pays exactly the LeafVoter's receipt token.
  function test_constructor_revertsWhen_leafChainTokenIsNotTheReceiptToken() public {
    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(address(aeroGaugeFactory), address(configManager), address(legacyReward));
  }

  function test_constructor_revertsWhen_emissionTokenHasNoCode() public {
    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(address(aeroGaugeFactory), address(configManager), makeAddr("notAToken"));
  }

  /// On Base the handler redeems the receipt token for the root Voter's TOKEN (AERO), so exactly that token pays out:
  /// the receipt token and any other deployed token (e.g. the pre-merger AERO) are rejected.
  function test_constructor_rootChain_requiresTheRootVoterToken() public {
    MockRewardToken baseXAero = new MockRewardToken("xAERO");
    MockRewardToken aero = new MockRewardToken("AERO");
    MockLeafVoter rootVoter = new MockLeafVoter(address(baseXAero), address(new MockRootEmissionsHandler()));
    MockRootMessageOrchestrator rootOrchestrator = new MockRootMessageOrchestrator(address(new MockVoter(address(aero))));
    MockRootLocalAdapter localAdapter = new MockRootLocalAdapter(address(rootOrchestrator));
    rootVoter.setOrchestrator(address(new MockMessageOrchestrator(address(localAdapter))));
    MockAeroGaugeFactory rootFactory = new MockAeroGaugeFactory(address(aeroNfpm), address(rootVoter));

    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(address(rootFactory), address(configManager), address(baseXAero));

    vm.expectRevert("Invalid emission token");
    new AerodromeFarmingStrategy(address(rootFactory), address(configManager), address(legacyReward));

    AerodromeFarmingStrategy strategy =
      new AerodromeFarmingStrategy(address(rootFactory), address(configManager), address(aero));
    assertEq(strategy.emissionToken(), address(aero));
  }

  /// The deploy script passes the chain's emission token to every gauge factory; a legacy one ignores it.
  function test_constructor_ignoresEmissionTokenForLegacyFactory() public {
    AerodromeFarmingStrategy strategy =
      new AerodromeFarmingStrategy(address(legacyGaugeFactory), address(configManager), address(xAero));
    assertEq(strategy.leafVoter(), address(0));
    assertEq(strategy.emissionToken(), address(0));
  }

  function test_constructor_treatsZeroLeafVoterAsLegacy() public {
    MockAeroGaugeFactory unwired = new MockAeroGaugeFactory(address(aeroNfpm), address(0));
    AerodromeFarmingStrategy strategy =
      new AerodromeFarmingStrategy(address(unwired), address(configManager), address(xAero));
    assertEq(strategy.leafVoter(), address(0));
    assertEq(strategy.emissionToken(), address(0));
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Legacy gauges: unchanged behaviour
  // ---------------------------------------------------------------------------------------------------------------

  function test_legacy_harvest_takesFeesInGaugeRewardToken() public {
    _stake(legacyStrategy, legacyNfpm, 1);
    legacyGauge.setPending(1, REWARD);

    _harvest(legacyStrategy, 1, false);

    assertEq(legacyReward.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(legacyReward.balanceOf(address(vault)), REWARD - _fee(REWARD));
    assertEq(legacyNfpm.ownerOf(1), address(legacyGauge), "still staked");
  }

  function test_legacy_withdraw_harvestsThenReturnsNft() public {
    _stake(legacyStrategy, legacyNfpm, 1);
    legacyGauge.setPending(1, REWARD);

    _withdraw(legacyStrategy, 1, true);

    assertEq(legacyNfpm.ownerOf(1), address(vault));
    assertEq(legacyReward.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(legacyReward.balanceOf(OWNER), REWARD - _fee(REWARD));
    assertEq(legacyReward.balanceOf(address(vault)), 0);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Aero gauges
  // ---------------------------------------------------------------------------------------------------------------

  function test_aero_deposit_stakesNft() public {
    _stake(aeroStrategy, aeroNfpm, 7);

    assertEq(aeroNfpm.ownerOf(7), address(aeroGauge));
    assertTrue(aeroGauge.stakedContains(address(vault), 7));
  }

  /// An inactive Aero gauge earns no emissions but would still take the staked position's swap fees.
  function test_aero_deposit_revertsWhen_gaugeInactive() public {
    leafVoter.setActivated(address(aeroGauge), false);
    aeroNfpm.mintPosition(address(vault), 7, TOKEN0, TOKEN1, TICK_SPACING);

    vm.expectRevert("Gauge not active");
    _exec(address(aeroStrategy), abi.encodeCall(AerodromeFarmingStrategy.deposit, (7)));
    assertEq(aeroNfpm.ownerOf(7), address(vault));
  }

  function test_aero_deposit_revertsWhen_emissionCapIsZero() public {
    aeroGaugeFactory.setEmissionCap(address(aeroGauge), 0);
    aeroNfpm.mintPosition(address(vault), 7, TOKEN0, TOKEN1, TICK_SPACING);

    vm.expectRevert("Gauge not active");
    _exec(address(aeroStrategy), abi.encodeCall(AerodromeFarmingStrategy.deposit, (7)));
    assertEq(aeroNfpm.ownerOf(7), address(vault));
  }

  /// Deactivating a gauge must never trap positions already staked in it.
  function test_aero_withdraw_worksAfterGaugeIsDeactivated() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    leafVoter.setActivated(address(aeroGauge), false);
    aeroGaugeFactory.setEmissionCap(address(aeroGauge), 0);

    _withdraw(aeroStrategy, 7, false);

    assertEq(aeroNfpm.ownerOf(7), address(vault));
  }

  function test_aero_depositZero_stakesLastMintedPosition() public {
    aeroNfpm.mintPosition(address(vault), 3, TOKEN0, TOKEN1, TICK_SPACING);
    aeroNfpm.mintPosition(address(vault), 9, TOKEN0, TOKEN1, TICK_SPACING);

    _exec(address(aeroStrategy), abi.encodeCall(AerodromeFarmingStrategy.deposit, (0)));

    assertTrue(aeroGauge.stakedContains(address(vault), 9));
    assertEq(aeroNfpm.ownerOf(3), address(vault));
  }

  function test_aero_harvest_claimsStakedPositionAndTakesFees() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 7;
    vm.expectCall(
      address(aeroGauge), abi.encodeCall(IAeroCLGauge.claimEmissions, (address(vault), address(vault), tokenIds))
    );
    _harvest(aeroStrategy, 7, false);

    assertEq(xAero.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(xAero.balanceOf(address(vault)), REWARD - _fee(REWARD));
    assertTrue(aeroGauge.stakedContains(address(vault), 7), "harvest keeps the position staked");
  }

  function test_aero_harvest_toVaultOwner() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);

    _harvest(aeroStrategy, 7, true);

    assertEq(xAero.balanceOf(OWNER), REWARD - _fee(REWARD));
    assertEq(xAero.balanceOf(address(vault)), 0);
  }

  function test_aero_harvest_revertsWhenMintFails() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);
    aeroGauge.setMintReverts(true);

    vm.expectRevert("CeilingExceeded");
    _harvest(aeroStrategy, 7, false);
    assertEq(aeroGauge.pending(7), REWARD, "nothing is lost: the emissions stay claimable");
  }

  function test_aero_withdraw_measuresTheGaugeClaimWithoutClaimingFirst() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);

    _withdraw(aeroStrategy, 7, false);

    assertEq(aeroGauge.claimCalls(), 0, "withdraw relies on the gauge's own claim");
    assertEq(aeroNfpm.ownerOf(7), address(vault));
    assertEq(xAero.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(xAero.balanceOf(address(vault)), REWARD - _fee(REWARD));
  }

  function test_aero_withdraw_toVaultOwner() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);

    _withdraw(aeroStrategy, 7, true);

    assertEq(xAero.balanceOf(OWNER), REWARD - _fee(REWARD));
    assertEq(xAero.balanceOf(address(vault)), 0);
  }

  /// A minting outage must not trap the NFT: the gauge defers the emissions and the withdrawal still goes through.
  function test_aero_withdraw_whenMintFails_stillReturnsNftAndDefersEmissions() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);
    aeroGauge.setMintReverts(true);

    _withdraw(aeroStrategy, 7, false);

    assertEq(aeroNfpm.ownerOf(7), address(vault));
    assertEq(aeroGauge.deferredEmissions(address(vault)), REWARD);
    assertEq(xAero.balanceOf(address(vault)), 0);
    assertEq(xAero.balanceOf(feeRecipient), 0);
  }

  function test_aero_harvest_afterWithdraw_claimsOnlyDeferredEmissions() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);
    aeroGauge.setMintReverts(true);
    _withdraw(aeroStrategy, 7, false);
    aeroGauge.setMintReverts(false);

    vm.expectCall(
      address(aeroGauge),
      abi.encodeCall(IAeroCLGauge.claimEmissions, (address(vault), address(vault), new uint256[](0)))
    );
    _harvest(aeroStrategy, 7, false);

    assertEq(aeroGauge.deferredEmissions(address(vault)), 0);
    assertEq(xAero.balanceOf(feeRecipient), _fee(REWARD));
    assertEq(xAero.balanceOf(address(vault)), REWARD - _fee(REWARD));
  }

  function test_aero_harvest_ofStakedPosition_alsoSweepsDeferredEmissions() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    _stake(aeroStrategy, aeroNfpm, 8);
    aeroGauge.setPending(7, REWARD);
    aeroGauge.setPending(8, 30e18);
    aeroGauge.setMintReverts(true);
    _withdraw(aeroStrategy, 7, false);
    aeroGauge.setMintReverts(false);

    _harvest(aeroStrategy, 8, false);

    uint256 claimed = REWARD + 30e18;
    assertEq(xAero.balanceOf(address(vault)), claimed - _fee(claimed));
    assertTrue(aeroGauge.stakedContains(address(vault), 8));
  }

  function test_aero_emergencyWithdraw_returnsNftAndForfeitsEmissions() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    aeroGauge.setPending(7, REWARD);
    aeroGauge.setEmergencyEnabled(true);

    _exec(address(aeroStrategy), abi.encodeCall(AerodromeFarmingStrategy.emergencyWithdraw, (7)));

    assertEq(aeroNfpm.ownerOf(7), address(vault));
    assertFalse(aeroGauge.stakedContains(address(vault), 7));
    assertEq(aeroGauge.pending(7), 0, "emissions forfeited");
    assertEq(xAero.balanceOf(address(vault)), 0);
    assertEq(xAero.balanceOf(feeRecipient), 0);
  }

  function test_aero_emergencyWithdraw_revertsUnlessEnabled() public {
    _stake(aeroStrategy, aeroNfpm, 7);

    vm.expectRevert(bytes("NE"));
    _exec(address(aeroStrategy), abi.encodeCall(AerodromeFarmingStrategy.emergencyWithdraw, (7)));
    assertEq(aeroNfpm.ownerOf(7), address(aeroGauge));
  }

  function test_legacy_emergencyWithdraw_reverts() public {
    _stake(legacyStrategy, legacyNfpm, 1);

    vm.expectRevert("Not an Aero gauge");
    _exec(address(legacyStrategy), abi.encodeCall(AerodromeFarmingStrategy.emergencyWithdraw, (1)));
  }

  function test_aero_harvest_ofWithdrawnPosition_revertsWhenNothingIsDeferred() public {
    _stake(aeroStrategy, aeroNfpm, 7);
    _withdraw(aeroStrategy, 7, false);

    vm.expectRevert(bytes("NS"));
    _harvest(aeroStrategy, 7, false);
  }
}
