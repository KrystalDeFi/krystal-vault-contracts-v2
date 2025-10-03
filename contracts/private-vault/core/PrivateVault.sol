// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../interfaces/core/IPrivateVault.sol";
import "../interfaces/core/IPrivateConfigManager.sol";

contract PrivateVault is Initializable, ReentrancyGuard, ERC721Holder, ERC1155Holder, IERC1271, IPrivateVault {
  using SafeERC20 for IERC20;

  // Magic value per EIP-1271
  bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

  address public override vaultOwner;
  address public vaultFactory;
  IPrivateConfigManager public configManager;

  mapping(address => bool) public admins;

  modifier onlyOwner() {
    require(msg.sender == vaultOwner, Unauthorized());
    _;
  }

  modifier onlyAuthorized() {
    require(
      admins[msg.sender] || msg.sender == vaultOwner || configManager.isWhitelistedCaller(msg.sender), Unauthorized()
    );
    _;
  }

  modifier whenNotPaused() {
    require(!configManager.isVaultPaused(), Paused());
    _;
  }

  /// @notice Initializes the vault
  /// @param _owner Owner of the vault
  /// @param _configManager Address of the whitelist manager
  function initialize(address _owner, address _configManager) public initializer {
    require(_configManager != address(0), ZeroAddress());

    // Cache variables to minimize storage writes
    configManager = IPrivateConfigManager(_configManager);
    vaultOwner = _owner;
    vaultFactory = msg.sender;
    admins[vaultFactory] = true;
  }

  /// @notice Batch multiple calls together (calls or delegatecalls)
  /// @param targets Array of targets to call
  /// @param data Array of data to pass with the calls
  /// @param callTypes Array of call types (CALL or DELEGATECALL)
  function multicall(address[] calldata targets, bytes[] calldata data, CallType[] calldata callTypes)
    external
    payable
    override
    nonReentrant
    onlyAuthorized
    whenNotPaused
  {
    require(targets.length == data.length, InvalidMulticallParams());
    require(targets.length == callTypes.length, InvalidMulticallParams());

    for (uint256 i = 0; i != data.length;) {
      if (targets[i] == address(0)) {
        unchecked {
          i++;
        }
        continue;
      }
      if ((msg.sender != vaultOwner || configManager.enforceTargetWhitelistForOwners()) && targets[i] != address(this))
      {
        require(configManager.isWhitelistedTarget(targets[i]), InvalidTarget(targets[i]));
      }

      bool success;
      bytes memory result;

      if (callTypes[i] == CallType.DELEGATECALL) (success, result) = targets[i].delegatecall(data[i]);
      else (success, result) = targets[i].call(data[i]);

      if (!success) {
        if (result.length == 0) revert StrategyDelegateCallFailed();
        assembly {
          revert(add(32, result), mload(result))
        }
      }
      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweep native token to the caller
  /// @param amount Amount of native token to sweep
  function sweepNativeToken(uint256 amount) external override nonReentrant onlyOwner {
    (bool success,) = msg.sender.call{ value: amount }("");
    require(success, "Failed to send native token");
  }

  /// @notice Sweeps the tokens to the caller
  /// @param tokens Tokens to sweep
  /// @param amounts Amounts of tokens to sweep
  function sweepToken(address[] calldata tokens, uint256[] calldata amounts) external override nonReentrant onlyOwner {
    for (uint256 i; i < tokens.length;) {
      IERC20 token = IERC20(tokens[i]);
      uint256 amount = amounts[i];
      token.safeTransfer(msg.sender, amount);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweeps the non-fungible tokens ERC721 to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  function sweepERC721(address[] calldata _tokens, uint256[] calldata _tokenIds)
    external
    override
    nonReentrant
    onlyOwner
  {
    for (uint256 i; i < _tokens.length;) {
      IERC721 token = IERC721(_tokens[i]);
      token.safeTransferFrom(address(this), msg.sender, _tokenIds[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Sweep ERC1155 tokens to the caller
  /// @param _tokens Tokens to sweep
  /// @param _tokenIds Token IDs to sweep
  /// @param _amounts Amounts of tokens to sweep
  function sweepERC1155(address[] calldata _tokens, uint256[] calldata _tokenIds, uint256[] calldata _amounts)
    external
    override
    nonReentrant
    onlyOwner
  {
    for (uint256 i; i < _tokens.length;) {
      IERC1155 token = IERC1155(_tokens[i]);
      uint256 amount = _amounts[i];
      token.safeTransferFrom(address(this), msg.sender, _tokenIds[i], amount, "");

      unchecked {
        i++;
      }
    }
  }

  /// @notice Deposits ERC20 tokens to the vault
  /// @param tokens Array of ERC20 token addresses
  /// @param amounts Array of amounts to deposit
  function depositErc20Tokens(address[] calldata tokens, uint256[] calldata amounts)
    external
    override
    nonReentrant
    onlyOwner
  {
    require(tokens.length == amounts.length, InvalidMulticallParams());

    for (uint256 i; i < tokens.length;) {
      require(amounts[i] > 0, InvalidAmount());
      IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Deposits ERC721 tokens to the vault
  /// @param tokens Array of ERC721 token addresses
  /// @param tokenIds Array of token IDs to deposit
  function depositErc721Tokens(address[] calldata tokens, uint256[] calldata tokenIds)
    external
    override
    nonReentrant
    onlyOwner
  {
    require(tokens.length == tokenIds.length, InvalidMulticallParams());

    for (uint256 i; i < tokens.length;) {
      IERC721(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenIds[i]);

      unchecked {
        i++;
      }
    }
  }

  /// @notice Deposits ERC1155 tokens to the vault
  /// @param tokens Array of ERC1155 token addresses
  /// @param tokenIds Array of token IDs to deposit
  /// @param amounts Array of amounts to deposit
  function depositErc1155Tokens(address[] calldata tokens, uint256[] calldata tokenIds, uint256[] calldata amounts)
    external
    override
    nonReentrant
    onlyOwner
  {
    require(tokens.length == tokenIds.length, InvalidMulticallParams());
    require(tokens.length == amounts.length, InvalidMulticallParams());

    for (uint256 i; i < tokens.length;) {
      require(amounts[i] > 0, InvalidAmount());
      IERC1155(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenIds[i], amounts[i], "");

      unchecked {
        i++;
      }
    }
  }

  /// @notice grant admin role to the address
  /// @param _address The address to which the admin role is granted
  function grantAdminRole(address _address) external override onlyOwner {
    admins[_address] = true;

    emit SetVaultAdmin(vaultFactory, _address, true);
  }

  /// @notice revoke admin role from the address
  /// @param _address The address from which the admin role is revoked
  function revokeAdminRole(address _address) external override onlyOwner {
    admins[_address] = false;

    emit SetVaultAdmin(vaultFactory, _address, false);
  }

  /// @notice EIP-1271 signature validation
  /// @param hash The hash of the data to be signed
  /// @param signature The signature to be validated
  /// @return magicValue The magic value if the signature is valid, otherwise 0xffffffff
  function isValidSignature(bytes32 hash, bytes memory signature) public view override returns (bytes4 magicValue) {
    bool success = SignatureChecker.isValidSignatureNow(vaultOwner, hash, signature);

    magicValue = success ? MAGIC_VALUE : bytes4("");
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  receive() external payable { }
}
