// SPDX-License-Identifier: GPL-2.0-or-later

using Midnight as midnight;

methods {
    function nonce(address) external returns (uint256) envfree;
    function MIDNIGHT() external returns (address) envfree;
    function midnight.isAuthorized(address, address) external returns (bool) envfree;
}

/// setIsAuthorizedWithSig is satisfiable.
rule satisfiable(env e, SetIsAuthorizedWithSig.Authorization authorization, SetIsAuthorizedWithSig.Signature signature) {
    setIsAuthorizedWithSig(e, authorization, signature);
    satisfy true;
}

/// setIsAuthorizedWithSig increments nonce and doesn't change other nonces.
rule effects(env e, SetIsAuthorizedWithSig.Authorization authorization, SetIsAuthorizedWithSig.Signature signature, address other) {
    require other != authorization.authorizer;
    uint256 nonceBefore = nonce(authorization.authorizer);
    uint256 otherNonceBefore = nonce(other);

    setIsAuthorizedWithSig(e, authorization, signature);

    assert nonce(authorization.authorizer) == nonceBefore + 1;
    assert nonce(other) == otherNonceBefore;
}

/// A nonce can't be reused.
rule nonceReplay(env e1, env e2, SetIsAuthorizedWithSig.Authorization auth1, SetIsAuthorizedWithSig.Signature sig1, SetIsAuthorizedWithSig.Authorization auth2, SetIsAuthorizedWithSig.Signature sig2) {
    uint256 nonceBefore = nonce(auth1.authorizer);

    setIsAuthorizedWithSig(e1, auth1, sig1);

    setIsAuthorizedWithSig@withrevert(e2, auth2, sig2);

    assert !lastReverted => nonce(auth1.authorizer) == nonceBefore + 2;
}
