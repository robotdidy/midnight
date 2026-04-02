// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {IMidnight, Authorization} from "../interfaces/IMidnight.sol";
import {Signature, AUTHORIZATION_TYPEHASH, EIP712_DOMAIN_TYPEHASH} from "../interfaces/IEcrecover.sol";

contract SetIsAuthorizedWithSig {
    event SetIsAuthorizedWithSig(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized, uint256 nonce
    );

    address public immutable MIDNIGHT;
    mapping(address => uint256) public nonce;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function setIsAuthorizedWithSig(Authorization memory authorization, Signature calldata signature) external {
        require(block.timestamp <= authorization.deadline, "expired");
        require(authorization.nonce == nonce[authorization.authorizer]++, "invalid nonce");

        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);
        require(
            signatory != address(0)
                && (signatory == authorization.authorizer
                    || IMidnight(MIDNIGHT).isAuthorized(authorization.authorizer, signatory)),
            "invalid signature"
        );

        emit SetIsAuthorizedWithSig(
            msg.sender, authorization.authorizer, authorization.authorized, authorization.isAuthorized, authorization.nonce
        );

        IMidnight(MIDNIGHT).setIsAuthorized(authorization.authorizer, authorization.authorized, authorization.isAuthorized);
    }
}
