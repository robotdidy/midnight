// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Signature, EIP712_DOMAIN_TYPEHASH, AUTHORIZATION_TYPEHASH} from "../src/interfaces/IEcrecover.sol";
import {Authorization} from "../src/interfaces/IMidnight.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRatifierTest is BaseTest {
    function makeAuthorization(address authorizer, address authorized, bool isAuth)
        internal
        view
        returns (Authorization memory)
    {
        return Authorization({
            authorizer: authorizer,
            authorized: authorized,
            isAuthorized: isAuth,
            nonce: setIsAuthorizedWithSig.nonce(authorizer),
            deadline: block.timestamp + 1 days
        });
    }

    function signAuthorization(Authorization memory authorization, address _signer)
        internal
        view
        returns (Signature memory)
    {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(setIsAuthorizedWithSig)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[_signer], digest);
        return Signature({v: v, r: r, s: s});
    }

    function testSetIsAuthorizedWithSig() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, borrower);

        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), true);
        assertEq(setIsAuthorizedWithSig.nonce(borrower), 1);

        auth = makeAuthorization(borrower, lender, false);
        sig = signAuthorization(auth, borrower);

        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), false);
        assertEq(setIsAuthorizedWithSig.nonce(borrower), 2);
    }

    function testSetIsAuthorizedWithSigPermissionless() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, borrower);

        // Anyone can submit — no caller auth needed
        vm.prank(otherLender);
        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), true);
        assertEq(setIsAuthorizedWithSig.nonce(borrower), 1);
    }

    function testSetIsAuthorizedWithSigInvalidSignature() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        Signature memory sig = signAuthorization(auth, lender); // wrong signer

        vm.expectRevert("invalid signature");
        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);

        assertEq(midnight.isAuthorized(borrower, lender), false);
        assertEq(setIsAuthorizedWithSig.nonce(borrower), 0);
    }

    function testSetIsAuthorizedWithSigExpired() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        auth.deadline = block.timestamp - 1;
        Signature memory sig = signAuthorization(auth, borrower);

        vm.expectRevert("expired");
        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);
    }

    function testSetIsAuthorizedWithSigInvalidNonce() public {
        Authorization memory auth = makeAuthorization(borrower, lender, true);
        auth.nonce = 999; // wrong nonce
        Signature memory sig = signAuthorization(auth, borrower);

        vm.expectRevert("invalid nonce");
        setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);
    }

    function testSetIsAuthorizedWithSigNonce(uint8 n) public {
        n = uint8(bound(n, 1, 32));

        for (uint8 i = 0; i < n; i++) {
            bool isAuth = i % 2 == 0;
            Authorization memory auth = makeAuthorization(borrower, lender, isAuth);
            Signature memory sig = signAuthorization(auth, borrower);

            setIsAuthorizedWithSig.setIsAuthorizedWithSig(auth, sig);

            assertEq(setIsAuthorizedWithSig.nonce(borrower), i + 1);
            assertEq(midnight.isAuthorized(borrower, lender), isAuth);
        }
    }
}
