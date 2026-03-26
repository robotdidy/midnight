// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {IRatifier} from "../interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "../libraries/ConstantsLib.sol";

contract EcrecoverRatifier is IRatifier {
    address public immutable MIDNIGHT;

    constructor(address midnight_) {
        MIDNIGHT = midnight_;
    }

    function onRatify(Offer memory offer, bytes32 root, bytes32[] memory, bytes memory data)
        external
        view
        returns (bytes32)
    {
        require(msg.sender == MIDNIGHT, "only midnight");

        Signature memory signature = abi.decode(data, (Signature));
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, MIDNIGHT));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, signature.v, signature.r, signature.s);

        return signer != address(0) && signer == offer.maker ? CALLBACK_SUCCESS : bytes32(0);
    }
}
