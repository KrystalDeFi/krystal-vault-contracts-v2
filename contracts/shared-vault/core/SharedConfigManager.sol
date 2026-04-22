// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/ISharedConfigManager.sol";
import "../interfaces/ISharedCommon.sol";

contract SharedConfigManager is OwnableUpgradeable, ISharedConfigManager {
  mapping(address => bool) public whitelistedTargets;
  mapping(address => bool) public whitelistedCallers;
  mapping(address => bool) public whitelistedNfpms;
  mapping(address => bool) public whitelistedSwapRouters;

  bool public override isVaultPaused = false;
  address public override feeRecipient;
  uint16 public override platformFeeBasisPoint;
  uint16 public override maxPositions = 20;

  /// @inheritdoc ISharedConfigManager
  uint8 public override minTokenPrecision = 5;

  function initialize(
    address _owner,
    address[] calldata _whitelistTargets,
    address[] calldata _whitelistCallers,
    address _feeRecipient,
    uint16 _platformFeeBasisPoint,
    address[] calldata _whitelistNfpms,
    address[] calldata _whitelistSwapRouters
  ) public initializer {
    require(_platformFeeBasisPoint <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    __Ownable_init(_owner);
    platformFeeBasisPoint = _platformFeeBasisPoint;

    uint256 length = _whitelistTargets.length;
    for (uint256 i; i < length; ) {
      whitelistedTargets[_whitelistTargets[i]] = true;
      unchecked {
        i++;
      }
    }

    length = _whitelistCallers.length;
    for (uint256 i; i < length; ) {
      whitelistedCallers[_whitelistCallers[i]] = true;
      unchecked {
        i++;
      }
    }

    length = _whitelistNfpms.length;
    for (uint256 i; i < length; ) {
      whitelistedNfpms[_whitelistNfpms[i]] = true;
      unchecked {
        i++;
      }
    }

    length = _whitelistSwapRouters.length;
    for (uint256 i; i < length; ) {
      whitelistedSwapRouters[_whitelistSwapRouters[i]] = true;
      unchecked {
        i++;
      }
    }

    feeRecipient = _feeRecipient;

    if (_whitelistTargets.length > 0) emit WhitelistTargetsUpdated(_whitelistTargets, true);
    if (_whitelistCallers.length > 0) emit WhitelistCallersUpdated(_whitelistCallers, true);
    if (_whitelistNfpms.length > 0) emit WhitelistNfpmsUpdated(_whitelistNfpms, true);
    if (_whitelistSwapRouters.length > 0) emit WhitelistSwapRoutersUpdated(_whitelistSwapRouters, true);
  }

  function setWhitelistTargets(address[] calldata targets, bool _isWhitelisted) external override onlyOwner {
    uint256 length = targets.length;
    for (uint256 i; i < length; ) {
      whitelistedTargets[targets[i]] = _isWhitelisted;
      unchecked {
        i++;
      }
    }
    emit WhitelistTargetsUpdated(targets, _isWhitelisted);
  }

  function isWhitelistedTarget(address target) external view override returns (bool) {
    return whitelistedTargets[target];
  }

  function setWhitelistCallers(address[] calldata callers, bool _isWhitelisted) external override onlyOwner {
    uint256 length = callers.length;
    for (uint256 i; i < length; ) {
      whitelistedCallers[callers[i]] = _isWhitelisted;
      unchecked {
        i++;
      }
    }
    emit WhitelistCallersUpdated(callers, _isWhitelisted);
  }

  function isWhitelistedCaller(address caller) external view override returns (bool) {
    return whitelistedCallers[caller];
  }

  function setWhitelistNfpms(address[] calldata nfpms, bool _isWhitelisted) external override onlyOwner {
    uint256 length = nfpms.length;
    for (uint256 i; i < length; ) {
      whitelistedNfpms[nfpms[i]] = _isWhitelisted;
      unchecked {
        i++;
      }
    }
    emit WhitelistNfpmsUpdated(nfpms, _isWhitelisted);
  }

  function isWhitelistedNfpm(address nfpm) external view override returns (bool) {
    return whitelistedNfpms[nfpm];
  }

  function setWhitelistSwapRouters(address[] calldata swapRouters, bool _isWhitelisted) external override onlyOwner {
    uint256 length = swapRouters.length;
    for (uint256 i; i < length; ) {
      whitelistedSwapRouters[swapRouters[i]] = _isWhitelisted;
      unchecked {
        i++;
      }
    }
    emit WhitelistSwapRoutersUpdated(swapRouters, _isWhitelisted);
  }

  function isWhitelistedSwapRouter(address swapRouter) external view override returns (bool) {
    return whitelistedSwapRouters[swapRouter];
  }

  function setVaultPaused(bool _isVaultPaused) external onlyOwner {
    isVaultPaused = _isVaultPaused;
    emit VaultPausedUpdated(_isVaultPaused);
  }

  function setFeeRecipient(address newFeeRecipient) external override onlyOwner {
    require(newFeeRecipient != address(0), ISharedCommon.ZeroAddress());

    emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);

    feeRecipient = newFeeRecipient;
  }

  function setPlatformFeeBasisPoint(uint16 basisPoints) external override onlyOwner {
    require(basisPoints <= 10_000, ISharedCommon.InvalidFeeBasisPoint());
    platformFeeBasisPoint = basisPoints;
  }

  function setMaxPositions(uint16 _maxPositions) external override onlyOwner {
    require(_maxPositions > 0, ISharedCommon.InvalidAmount());
    maxPositions = _maxPositions;
    emit MaxPositionsUpdated(_maxPositions);
  }

  function setMinTokenPrecision(uint8 precision) external override onlyOwner {
    minTokenPrecision = precision;
    emit MinTokenPrecisionUpdated(precision);
  }
}
