// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {SStore2} from "../SStore2.sol";
import {Obligation} from "../interfaces/IMorphoV2.sol";

bytes constant SSTORE2_BYTECODE =
    hex"60806040523460845760c180380380601581609c565b9283398101906020818303126084578051906001600160401b0382116084570181601f8201121560845780516001600160401b038111608857605f601f8201601f1916602001609c565b91818352602083019360208383010111608457815f926020809301865e830101525190f35b5f80fd5b634e487b7160e01b5f52604160045260245ffd5b6040519190601f01601f191682016001600160401b0381118382101760885760405256fe";

library IdLib {
    function toId(Obligation memory obligation, uint256 chainid, address morphoV2) internal pure returns (bytes32) {
        bytes memory sstore2Data = abi.encode(obligation, chainid, morphoV2);
        bytes memory creationCode = abi.encodePacked(SSTORE2_BYTECODE, abi.encode(sstore2Data));
        return keccak256(creationCode);
    }

    function idToObligation(address morphoV2, bytes32 id) internal view returns (Obligation memory) {
        address create2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
        (Obligation memory obligation,,) = abi.decode(create2Address.code, (Obligation, uint256, address));
        return obligation;
    }

    function sstore2(Obligation memory obligation) internal {
        new SStore2{salt: bytes32(0)}(abi.encode(obligation, block.chainid, address(this)));
    }
}
