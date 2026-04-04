// SPDX-License-Identifier: GPL-2.0-or-later

using Midnight as midnight;

methods {
    function nonce(address) external returns (uint256) envfree;
    function MIDNIGHT() external returns (address) envfree;
    function midnight.isAuthorized(address, address) external returns (bool) envfree;
}

/// EcrecoverAuthorizer is satisfiable.
rule satisfiable(env e, EcrecoverAuthorizer.Authorization authorization, EcrecoverAuthorizer.Signature signature) {
    setIsAuthorized(e, authorization, signature);
    satisfy true;
}

/// EcrecoverAuthorizer increments nonce and doesn't change other nonces.
rule effects(env e, EcrecoverAuthorizer.Authorization authorization, EcrecoverAuthorizer.Signature signature, address other) {
    require other != authorization.authorizer;
    uint256 nonceBefore = nonce(authorization.authorizer);
    uint256 otherNonceBefore = nonce(other);

    setIsAuthorized(e, authorization, signature);

    assert nonce(authorization.authorizer) == nonceBefore + 1;
    assert nonce(other) == otherNonceBefore;
}

/// A nonce can't be reused.
rule nonceReplay(env e1, env e2, EcrecoverAuthorizer.Authorization auth1, EcrecoverAuthorizer.Signature sig1, EcrecoverAuthorizer.Authorization auth2, EcrecoverAuthorizer.Signature sig2) {
    require auth2.authorizer == auth1.authorizer;
    require auth2.nonce == nonce(auth1.authorizer);

    setIsAuthorized(e1, auth1, sig1);

    setIsAuthorized@withrevert(e2, auth2, sig2);

    assert lastReverted;
}
