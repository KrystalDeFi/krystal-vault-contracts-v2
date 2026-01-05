// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/public-vault/core/ConfigManager.sol";
import "../../contracts/public-vault/strategies/merkl/MerklAutomator.sol";
import "../../contracts/public-vault/strategies/merkl/MerklStrategy.sol";
import "../../contracts/public-vault/interfaces/core/IVault.sol";
import "../../contracts/public-vault/interfaces/strategies/IMerklStrategy.sol";
import "../../contracts/public-vault/libraries/AssetLib.sol";
import "../../test/TestCommon.t.sol";

// Mock ERC20 token for testing
contract MockERC20 {
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, "Insufficient balance");
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(balanceOf[from] >= amount, "Insufficient balance");
    require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    allowance[from][msg.sender] -= amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

// Mock ERC721 token for testing
contract MockERC721 {
  mapping(uint256 => address) private _owners;
  mapping(address => uint256) public balanceOf;

  function mint(address to, uint256 tokenId) external {
    require(_owners[tokenId] == address(0), "Token already minted");
    _owners[tokenId] = to;
    balanceOf[to]++;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    address owner = _owners[tokenId];
    require(owner != address(0), "Token does not exist");
    return owner;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    require(_owners[tokenId] == from, "Not the owner");
    _owners[tokenId] = to;
    balanceOf[from]--;
    balanceOf[to]++;
  }

  function approve(address, uint256) external pure returns (bool) {
    return true;
  }

  function getApproved(uint256) external pure returns (address) {
    return address(0);
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

// Mock ERC1155 token for testing
contract MockERC1155 {
  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  function mint(address to, uint256 tokenId, uint256 amount) external {
    balanceOf[to][tokenId] += amount;
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes calldata) external {
    require(balanceOf[from][tokenId] >= amount, "Insufficient balance");
    balanceOf[from][tokenId] -= amount;
    balanceOf[to][tokenId] += amount;
  }

  function setApprovalForAll(address, bool) external pure { }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}

contract MerklAutomatorTest is TestCommon {
  MerklAutomator public autoClaimer;
  MerklStrategy public strategy;
  IVault public vault;
  uint256 public ownerPrivateKey = 0xABCD;
  address public owner = vm.addr(ownerPrivateKey);
  address public user = makeAddr("user");
  address public token = makeAddr("rewardToken");
  address public principalToken = makeAddr("principalToken");

  function setUp() public {
    ConfigManager configManager = new ConfigManager();
    configManager.initialize(
      owner,
      new address[](0),
      new address[](0),
      new address[](0),
      new address[](0),
      new address[](0),
      new uint256[](0),
      0,
      0,
      0,
      address(0),
      new address[](0),
      new address[](0),
      new bytes[](0)
    );
    address[] memory whitelistedSigners = new address[](1);
    whitelistedSigners[0] = owner;
    vm.startPrank(owner);
    configManager.whitelistSigner(whitelistedSigners, true);
    vm.stopPrank();
    // Deploy test contracts
    strategy = new MerklStrategy(address(this)); // Using test contract as config manager
    address[] memory allowedStrategies = new address[](1);
    allowedStrategies[0] = address(strategy);
    autoClaimer = new MerklAutomator(owner, address(configManager));

    // Setup mock vault
    vault = IVault(makeAddr("vault"));
    vm.mockCall(address(vault), abi.encodeWithSelector(IVault.vaultOwner.selector), abi.encode(owner));
  }

  function test_ClaimRewards() public {
    // Prepare claim params
    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days,
      signature: _signClaimParams(ownerPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap), params: abi.encode(params)
      })
    );

    // Verify vault allocate was called
    vm.expectCall(
      address(vault),
      abi.encodeWithSelector(IVault.allocate.selector, new AssetLib.Asset[](0), address(strategy), 0, allocateData)
    );

    // Test claim by user
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function test_RevertIf_ExpiredSignature() public {
    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days, // expired
      signature: _signClaimParams(ownerPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap), params: abi.encode(params)
      })
    );

    skip(2 days); // skip to make signature expired
    vm.expectRevert(ICommon.SignatureExpired.selector);
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function test_RevertIf_InvalidSigner() public {
    // Sign with non-whitelisted private key
    uint256 invalidPrivateKey = 12_345;

    IMerklStrategy.ClaimAndSwapParams memory params = IMerklStrategy.ClaimAndSwapParams({
      distributor: makeAddr("distributor"),
      token: token,
      amount: 100 ether,
      proof: new bytes32[](0),
      swapRouter: makeAddr("swapRouter"),
      swapData: abi.encode("swap"),
      amountOutMin: 90 ether,
      deadline: uint32(uint32(block.timestamp)) + 1 days,
      signature: _signClaimParams(invalidPrivateKey)
    });

    bytes memory allocateData = abi.encode(
      ICommon.Instruction({
        instructionType: uint8(IMerklStrategy.InstructionType.ClaimAndSwap), params: abi.encode(params)
      })
    );

    vm.expectRevert(ICommon.InvalidSigner.selector);
    vm.prank(user);
    autoClaimer.executeAllocate(vault, new AssetLib.Asset[](0), strategy, 0, allocateData, "", "");
  }

  function _signClaimParams(uint256 signer) internal returns (bytes memory) {
    bytes32 messageHash = keccak256(
      abi.encodePacked(
        makeAddr("distributor"),
        token,
        uint256(100 ether),
        new bytes32[](0),
        makeAddr("swapRouter"),
        abi.encode("swap"),
        uint256(90 ether),
        uint32(block.timestamp) + 1 days
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, messageHash);
    return abi.encodePacked(r, s, v);
  }

  // ========== Sweep Tests ==========

  MockERC20 public mockERC20;
  MockERC721 public mockERC721;
  MockERC1155 public mockERC1155;
  address public constant NON_OWNER = address(0x999);

  function test_sweepNativeToken_success() public {
    uint256 amount = 1 ether;
    vm.deal(address(autoClaimer), amount);

    uint256 ownerBalanceBefore = owner.balance;

    vm.prank(owner);
    autoClaimer.sweepNativeToken(amount);

    assertEq(owner.balance, ownerBalanceBefore + amount);
    assertEq(address(autoClaimer).balance, 0);
  }

  function test_sweepNativeToken_unauthorized() public {
    uint256 amount = 1 ether;
    vm.deal(address(autoClaimer), amount);

    vm.prank(NON_OWNER);
    vm.expectRevert();
    autoClaimer.sweepNativeToken(amount);
  }

  function test_sweepERC20_success() public {
    mockERC20 = new MockERC20();
    uint256 amount = 1000;

    // Mint tokens to automator
    mockERC20.mint(address(autoClaimer), amount);

    uint256 ownerBalanceBefore = mockERC20.balanceOf(owner);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(owner);
    autoClaimer.sweepERC20(tokens, amounts);

    assertEq(mockERC20.balanceOf(owner), ownerBalanceBefore + amount);
    assertEq(mockERC20.balanceOf(address(autoClaimer)), 0);
  }

  function test_sweepERC20_zero_token() public {
    mockERC20 = new MockERC20();
    uint256 amount = 1000;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(owner);
    vm.expectRevert("ZeroAddress");
    autoClaimer.sweepERC20(tokens, amounts);
  }

  function test_sweepERC20_unauthorized() public {
    mockERC20 = new MockERC20();
    uint256 amount = 1000;
    mockERC20.mint(address(autoClaimer), amount);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC20);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(NON_OWNER);
    vm.expectRevert();
    autoClaimer.sweepERC20(tokens, amounts);
  }

  function test_sweepERC721_success() public {
    mockERC721 = new MockERC721();
    uint256 tokenId = 1;

    // Mint NFT to automator
    mockERC721.mint(address(autoClaimer), tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC721);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(owner);
    autoClaimer.sweepERC721(tokens, tokenIds);

    assertEq(mockERC721.ownerOf(tokenId), owner);
    assertEq(mockERC721.balanceOf(address(autoClaimer)), 0);
  }

  function test_sweepERC721_zero_token() public {
    mockERC721 = new MockERC721();
    uint256 tokenId = 1;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.prank(owner);
    vm.expectRevert("ZeroAddress");
    autoClaimer.sweepERC721(tokens, tokenIds);
  }

  function test_sweepERC1155_success() public {
    mockERC1155 = new MockERC1155();
    uint256 tokenId = 1;
    uint256 amount = 100;

    // Mint ERC1155 tokens to automator
    mockERC1155.mint(address(autoClaimer), tokenId, amount);

    uint256 ownerBalanceBefore = mockERC1155.balanceOf(owner, tokenId);

    address[] memory tokens = new address[](1);
    tokens[0] = address(mockERC1155);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(owner);
    autoClaimer.sweepERC1155(tokens, tokenIds, amounts);

    assertEq(mockERC1155.balanceOf(owner, tokenId), ownerBalanceBefore + amount);
    assertEq(mockERC1155.balanceOf(address(autoClaimer), tokenId), 0);
  }

  function test_sweepERC1155_zero_token() public {
    mockERC1155 = new MockERC1155();
    uint256 tokenId = 1;
    uint256 amount = 100;

    address[] memory tokens = new address[](1);
    tokens[0] = address(0);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    vm.prank(owner);
    vm.expectRevert("ZeroAddress");
    autoClaimer.sweepERC1155(tokens, tokenIds, amounts);
  }
}
