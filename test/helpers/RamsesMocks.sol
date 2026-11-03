// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {
  IRamsesV3PositionManager
} from "../../contracts/common/interfaces/protocols/ramses/IRamsesV3PositionManager.sol";
import { IRamsesRewardValidator } from "../../contracts/common/interfaces/protocols/ramses/IRamsesRewardValidator.sol";

// Mocks of the Ramses CL stack (ramses-v3-contracts) reproducing what RamsesFarmingStrategy depends on: rewards are
// claimed through the position manager, which pays the NFT's current owner, and a gauge forfeits a claim its reward
// validator flags (one made too soon after the position's last liquidity change).

contract MockRamsesToken is ERC20 {
  constructor(string memory symbol) ERC20(symbol, symbol) { }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockRamsesPool {
  address public immutable token0;
  address public immutable token1;
  int24 public immutable tickSpacing;

  constructor(address _token0, address _token1, int24 _tickSpacing) {
    require(_token0 < _token1, "token order");
    token0 = _token0;
    token1 = _token1;
    tickSpacing = _tickSpacing;
  }
}

contract MockRamsesVoter {
  address public nfpManager;
  address public immutable ram;
  mapping(address => address) public gaugeForPool;

  constructor(address _ram) {
    ram = _ram;
  }

  function setNfpManager(address _nfpManager) external {
    nfpManager = _nfpManager;
  }

  function setGauge(address pool, address gauge) external {
    gaugeForPool[pool] = gauge;
  }
}

/// @dev Ramses' anti-sybil validator: flags a claim made less than `threshold` seconds after the position's last
///      liquidity change.
contract MockRamsesRewardValidator is IRamsesRewardValidator {
  IRamsesV3PositionManager public immutable nfpm;
  uint256 public immutable threshold;

  constructor(address _nfpm, uint256 _threshold) {
    nfpm = IRamsesV3PositionManager(_nfpm);
    threshold = _threshold;
  }

  function validateReward(address, address, bytes32, address, uint256 index, int24, int24, address)
    external
    view
    returns (bool)
  {
    return block.timestamp < uint256(nfpm.positionLastModified(index)) + threshold;
  }
}

/// @dev GaugeV3 claim semantics: only the position manager claims, paying the NFT's owner; a claim the validator flags
///      (or a reverting validator) is forfeited to `forfeitSink` (r33 on the real chain) instead.
contract MockRamsesGauge {
  address public immutable nfpm;
  address public immutable pool;
  address public immutable rewardValidator;
  address public immutable forfeitSink;
  mapping(uint256 => mapping(address => uint256)) internal _pending;

  constructor(address _nfpm, address _pool, address _rewardValidator, address _forfeitSink) {
    nfpm = _nfpm;
    pool = _pool;
    rewardValidator = _rewardValidator;
    forfeitSink = _forfeitSink;
  }

  function setPending(uint256 tokenId, address token, uint256 amount) external {
    _pending[tokenId][token] = amount;
  }

  function earned(address token, uint256 tokenId) external view returns (uint256) {
    return _pending[tokenId][token];
  }

  function getRewardForOwner(uint256 tokenId, address[] calldata tokens) external {
    require(msg.sender == nfpm, "not an authorized claimer");
    address owner = ERC721(nfpm).ownerOf(tokenId);
    (,,, int24 tickLower, int24 tickUpper,,,,,) = IRamsesV3PositionManager(nfpm).positions(tokenId);
    bool slash = _shouldSlash(owner, tokenId, tickLower, tickUpper);
    for (uint256 i; i < tokens.length; i++) {
      uint256 amount = _pending[tokenId][tokens[i]];
      if (amount == 0) continue;
      _pending[tokenId][tokens[i]] = 0;
      MockRamsesToken(tokens[i]).mint(slash ? forfeitSink : owner, amount);
    }
  }

  function _shouldSlash(address owner, uint256 tokenId, int24 tickLower, int24 tickUpper) internal view returns (bool) {
    bytes32 positionHash = keccak256(abi.encodePacked(nfpm, tokenId, tickLower, tickUpper));
    try IRamsesRewardValidator(rewardValidator)
      .validateReward(nfpm, owner, positionHash, tx.origin, tokenId, tickLower, tickUpper, pool) returns (
      bool slash
    ) {
      return slash;
    } catch {
      return true;
    }
  }
}

contract MockRamsesNfpm is ERC721Enumerable {
  struct Pos {
    address pool;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint32 lastModified;
  }

  MockRamsesVoter public immutable voter;
  uint256 public nextId = 1;
  mapping(uint256 => Pos) internal _pos;

  constructor(MockRamsesVoter _voter) ERC721("Ramses V3 Non Fungible Position", "RAM-V3-NFP") {
    voter = _voter;
  }

  function positions(uint256 tokenId)
    external
    view
    returns (address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128)
  {
    Pos memory p = _pos[tokenId];
    require(p.pool != address(0), "InvalidTokenId");
    MockRamsesPool pool = MockRamsesPool(p.pool);
    return (pool.token0(), pool.token1(), pool.tickSpacing(), p.tickLower, p.tickUpper, p.liquidity, 0, 0, 0, 0);
  }

  function positionLastModified(uint256 tokenId) external view returns (uint32) {
    return _pos[tokenId].lastModified;
  }

  /// @dev Claims `tokens` for the position's current owner; only the owner or an approved address may claim.
  function getReward(uint256 tokenId, address[] calldata tokens) external {
    _checkAuthorized(_ownerOf(tokenId), msg.sender, tokenId);
    MockRamsesGauge(voter.gaugeForPool(_pos[tokenId].pool)).getRewardForOwner(tokenId, tokens);
  }

  /// @dev A position minted to `to` without moving tokens; its anti-sybil timer starts now.
  function mintPositionTo(address to, address pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
    external
    returns (uint256 tokenId)
  {
    tokenId = nextId++;
    _pos[tokenId] = Pos(pool, tickLower, tickUpper, liquidity, uint32(block.timestamp));
    _mint(to, tokenId);
  }
}
