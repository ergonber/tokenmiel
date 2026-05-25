// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @title DocumentHashes
/// @notice Helpers para manejo de hashes SHA-256 de documentos legales.
/// @dev Pure functions. Los hashes se calculan off-chain (backend) y se publican on-chain.
library DocumentHashes {
    /// @notice Combina dos hashes en uno (Merkle-style).
    /// @param a Primer hash.
    /// @param b Segundo hash.
    /// @return combined Hash combinado: keccak256(a || b) (con ordering consistente).
    /// @dev El ordenamiento determinista evita el problema de second preimage.
    function combine(bytes32 a, bytes32 b) internal pure returns (bytes32 combined) {
        if (a < b) {
            return keccak256(abi.encodePacked(a, b));
        }
        return keccak256(abi.encodePacked(b, a));
    }

    /// @notice Verifica que un hash no sea el hash vacío (todos ceros).
    /// @param hash Hash a verificar.
    /// @return isValid True si hash != bytes32(0).
    function isValid(bytes32 hash) internal pure returns (bool) {
        return hash != bytes32(0);
    }

    /// @notice Hashes de un array de hashes en un solo root (Merkle root simple).
    /// @param hashes Array de hashes.
    /// @return root Hash combinado de todos.
    function rootOf(bytes32[] memory hashes) internal pure returns (bytes32 root) {
        if (hashes.length == 0) return bytes32(0);
        if (hashes.length == 1) return hashes[0];

        root = hashes[0];
        for (uint256 i = 1; i < hashes.length; i++) {
            root = combine(root, hashes[i]);
        }
    }
}
