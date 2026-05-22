// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ConfigManager } from "../../contracts/public-vault/core/ConfigManager.sol";
import { Vault } from "../../contracts/public-vault/core/Vault.sol";
import { ICommon } from "../../contracts/public-vault/interfaces/ICommon.sol";
import { IStrategy } from "../../contracts/public-vault/interfaces/strategies/IStrategy.sol";
import { AssetLib } from "../../contracts/public-vault/libraries/AssetLib.sol";
import { DropPositionStrategy } from "../../contracts/public-vault/strategies/DropPositionStrategy.sol";

contract DropPositionMockERC20 is ERC20 {
  constructor() ERC20("Principal", "PRIN") { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract DropPositionMockERC721 {
  mapping(uint256 => address) private _owners;
  mapping(address => uint256) public balanceOf;
  mapping(uint256 => address) public getApproved;
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  function mint(address to, uint256 tokenId) external {
    require(_owners[tokenId] == address(0), "minted");
    _owners[tokenId] = to;
    balanceOf[to]++;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    address owner = _owners[tokenId];
    require(owner != address(0), "missing");
    return owner;
  }

  function approve(address spender, uint256 tokenId) external {
    require(_owners[tokenId] == msg.sender, "not owner");
    getApproved[tokenId] = spender;
  }

  function setApprovalForAll(address operator, bool approved) external {
    isApprovedForAll[msg.sender][operator] = approved;
  }

  function transferFrom(address from, address to, uint256 tokenId) public {
    _transfer(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) external {
    _transfer(from, to, tokenId);
  }

  function _transfer(address from, address to, uint256 tokenId) internal {
    require(_owners[tokenId] == from, "not owner");
    require(
      msg.sender == from || getApproved[tokenId] == msg.sender || isApprovedForAll[from][msg.sender], "not approved"
    );
    _owners[tokenId] = to;
    getApproved[tokenId] = address(0);
    balanceOf[from]--;
    balanceOf[to]++;
  }
}

contract DropPositionSeedStrategy is IStrategy {
  function valueOf(AssetLib.Asset calldata asset, address) external pure returns (uint256) {
    return asset.amount;
  }

  function convert(AssetLib.Asset[] calldata, VaultConfig calldata, FeeConfig calldata, bytes calldata data)
    external
    payable
    returns (AssetLib.Asset[] memory returnAssets)
  {
    (address nfpm, uint256 tokenId, address strategy) = abi.decode(data, (address, uint256, address));
    returnAssets = new AssetLib.Asset[](1);
    returnAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC721, strategy, nfpm, tokenId, 1);
  }

  function harvest(AssetLib.Asset calldata, address, uint256, VaultConfig calldata, FeeConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function convertFromPrincipal(AssetLib.Asset calldata, uint256, VaultConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function convertToPrincipal(AssetLib.Asset memory, uint256, uint256, VaultConfig calldata, FeeConfig calldata)
    external
    payable
    returns (AssetLib.Asset[] memory)
  {
    revert InvalidInstructionType();
  }

  function revalidate(AssetLib.Asset calldata, VaultConfig calldata) external pure { }
}

contract DropPositionStrategyTest is Test {
  address private constant VAULT_OWNER = address(0xA11CE);
  address private constant OPERATOR = address(0xB0B);

  ConfigManager private configManager;
  Vault private vault;
  DropPositionMockERC20 private principalToken;
  DropPositionMockERC721 private nfpm;
  DropPositionSeedStrategy private seedStrategy;
  DropPositionStrategy private dropStrategy;
  uint256 private nextBlock;

  function setUp() public {
    principalToken = new DropPositionMockERC20();
    nfpm = new DropPositionMockERC721();
    seedStrategy = new DropPositionSeedStrategy();

    configManager = new ConfigManager();
    configManager.initialize(
      address(this),
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

    dropStrategy = new DropPositionStrategy(address(configManager));

    address[] memory strategies = new address[](2);
    strategies[0] = address(seedStrategy);
    strategies[1] = address(dropStrategy);
    configManager.whitelistStrategy(strategies, true);

    principalToken.mint(address(this), 100 ether);

    vault = new Vault();
    principalToken.transfer(address(vault), 100 ether);

    ICommon.VaultCreateParams memory params = ICommon.VaultCreateParams({
      name: "Drop Test Vault",
      symbol: "DTV",
      principalTokenAmount: 100 ether,
      vaultOwnerFeeBasisPoint: 0,
      config: ICommon.VaultConfig({
        allowDeposit: true,
        rangeStrategyType: 0,
        tvlStrategyType: 0,
        principalToken: address(principalToken),
        supportedAddresses: new address[](0)
      })
    });

    vault.initialize(params, VAULT_OWNER, OPERATOR, address(configManager), address(0));
    vault.grantAdminRole(OPERATOR);
    nextBlock = block.number;
  }

  function test_dropPosition_transfersNftToOperatorAndRemovesInventoryAsset() public {
    uint256 tokenId = 123;
    _seedTrackedPosition(tokenId);

    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC721, address(seedStrategy), address(nfpm), tokenId, 1);

    ICommon.Instruction memory instruction =
      ICommon.Instruction({ instructionType: uint8(DropPositionStrategy.InstructionType.DropPosition), params: "" });

    _rollNextBlock();
    vault.allocate(inputAssets, dropStrategy, 0, abi.encode(instruction));

    assertEq(nfpm.ownerOf(tokenId), OPERATOR);
    assertFalse(_inventoryContains(address(nfpm), tokenId));
  }

  function test_recoverPosition_pullsNftFromOperatorAndReAddsInventoryAsset() public {
    uint256 tokenId = 456;
    _seedTrackedPosition(tokenId);

    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC721, address(seedStrategy), address(nfpm), tokenId, 1);

    ICommon.Instruction memory instruction =
      ICommon.Instruction({ instructionType: uint8(DropPositionStrategy.InstructionType.DropPosition), params: "" });

    _rollNextBlock();
    vault.allocate(inputAssets, dropStrategy, 0, abi.encode(instruction));

    vm.prank(OPERATOR);
    nfpm.approve(address(vault), tokenId);

    DropPositionStrategy.RecoverPositionParams memory recoverParams = DropPositionStrategy.RecoverPositionParams({
      nfpm: address(nfpm), tokenId: tokenId, strategy: address(seedStrategy)
    });
    instruction = ICommon.Instruction({
      instructionType: uint8(DropPositionStrategy.InstructionType.RecoverPosition), params: abi.encode(recoverParams)
    });

    _rollNextBlock();
    vm.prank(OPERATOR);
    vault.allocate(new AssetLib.Asset[](0), dropStrategy, 0, abi.encode(instruction));

    assertEq(nfpm.ownerOf(tokenId), address(vault));

    AssetLib.Asset memory recovered = _inventoryAsset(address(nfpm), tokenId);
    assertEq(recovered.strategy, address(seedStrategy));
    assertEq(recovered.amount, 1);
  }

  function test_recoverPosition_revertsWhenCallerIsNotOperator() public {
    uint256 tokenId = 789;
    _seedTrackedPosition(tokenId);
    _dropTrackedPosition(tokenId);

    vm.prank(OPERATOR);
    nfpm.approve(address(vault), tokenId);

    DropPositionStrategy.RecoverPositionParams memory recoverParams = DropPositionStrategy.RecoverPositionParams({
      nfpm: address(nfpm), tokenId: tokenId, strategy: address(seedStrategy)
    });
    ICommon.Instruction memory instruction = ICommon.Instruction({
      instructionType: uint8(DropPositionStrategy.InstructionType.RecoverPosition), params: abi.encode(recoverParams)
    });

    _rollNextBlock();
    vm.expectRevert(DropPositionStrategy.Unauthorized.selector);
    vault.allocate(new AssetLib.Asset[](0), dropStrategy, 0, abi.encode(instruction));
  }

  function _seedTrackedPosition(uint256 tokenId) private {
    nfpm.mint(address(vault), tokenId);
    _rollNextBlock();
    vault.allocate(new AssetLib.Asset[](0), seedStrategy, 0, abi.encode(address(nfpm), tokenId, address(seedStrategy)));
    assertEq(nfpm.ownerOf(tokenId), address(vault));
    assertTrue(_inventoryContains(address(nfpm), tokenId));
  }

  function _dropTrackedPosition(uint256 tokenId) private {
    AssetLib.Asset[] memory inputAssets = new AssetLib.Asset[](1);
    inputAssets[0] = AssetLib.Asset(AssetLib.AssetType.ERC721, address(seedStrategy), address(nfpm), tokenId, 1);

    ICommon.Instruction memory instruction =
      ICommon.Instruction({ instructionType: uint8(DropPositionStrategy.InstructionType.DropPosition), params: "" });

    _rollNextBlock();
    vault.allocate(inputAssets, dropStrategy, 0, abi.encode(instruction));
  }

  function _inventoryContains(address token, uint256 tokenId) private view returns (bool) {
    AssetLib.Asset[] memory assets = vault.getInventory();
    for (uint256 i; i < assets.length; i++) {
      if (assets[i].token == token && assets[i].tokenId == tokenId) return true;
    }
    return false;
  }

  function _inventoryAsset(address token, uint256 tokenId) private view returns (AssetLib.Asset memory) {
    AssetLib.Asset[] memory assets = vault.getInventory();
    for (uint256 i; i < assets.length; i++) {
      if (assets[i].token == token && assets[i].tokenId == tokenId) return assets[i];
    }
    revert("missing inventory asset");
  }

  function _rollNextBlock() private {
    nextBlock++;
    vm.roll(nextBlock);
  }
}
