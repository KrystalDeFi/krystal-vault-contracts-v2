// SPDX-License-Identifier: BUSL-1.1
// modified version of @openzeppelin
pragma solidity ^0.8.28;

import "../libraries/StructHash.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract CustomEIP712 {
  bytes32 private constant TYPE_HASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  bytes32 public immutable DOMAIN_SEPARATOR;

  constructor(string memory name, string memory version) {
    DOMAIN_SEPARATOR =
      keccak256(abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, address(this)));
  }

  /// @dev Recover signer of EIP712 signature
  /// @param order ABI encoded order
  /// @param signature Signature of the order
  /// @return Signer of the order
  function _recover(bytes memory order, bytes memory signature) internal view returns (address) {
    bytes32 digest = _hashTypedDataV4(StructHash._hash(order));
    return ECDSA.recover(digest, signature);
  }

  /// @dev Convert to typed data hash
  /// @param structHash Hash of the struct
  function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
    return toTypedDataHash(DOMAIN_SEPARATOR, structHash);
  }

  /**
   * @dev Returns the keccak256 digest of an EIP-712 typed data (EIP-191 version `0x01`).
   *
   * The digest is calculated from a `domainSeparator` and a `structHash`, by prefixing them with
   * `\x19\x01` and hashing the result. It corresponds to the hash signed by the
   * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`] JSON-RPC method as part of EIP-712.
   *
   * See {ECDSA-recover}.
   */
  function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
    /// @solidity memory-safe-assembly
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, hex"1901")
      mstore(add(ptr, 0x02), domainSeparator)
      mstore(add(ptr, 0x22), structHash)
      digest := keccak256(ptr, 0x42)
    }
  }
}
