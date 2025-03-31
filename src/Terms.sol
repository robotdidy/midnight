// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./libraries/Math.sol";
import {MathLib, WAD} from "./libraries/MathLib.sol";
import {SharesMathLib} from "./libraries/SharesMathLib.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITerms.sol";

contract Terms is ITerms {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    /// CONSTANTS ///

    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(bool lend,address offering,uint256 assets,address loanToken,Collateral[] collaterals,uint256 maturity,uint256 price)"
    );

    uint256 public constant ORACLE_PRICE_SCALE = 1e36;

    /// STORAGE ///

    // Terms.
    mapping(address => mapping(bytes32 => uint256)) public bondSharesOf;
    mapping(address => mapping(bytes32 => uint256)) public debtSharesOf;
    mapping(bytes32 => uint256) public withdrawableShares;
    mapping(bytes32 => Market) public market;
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public collateralOf;
    // Offers.
    mapping(bytes => uint256) public consumed;

    /// ENTRY-POINTS ///

    /// @dev This function is used for both primary and secondary markets.
    function MATCH(Offer memory buyOffer, Signature memory buySig, Offer memory sellOffer, Signature memory sellSig)
        public
    {
        _checkOffers(buyOffer, buySig, sellOffer, sellSig);

        uint256 amount = Math.min(
            buyOffer.assets - consumed[abi.encode(buyOffer)], sellOffer.assets - consumed[abi.encode(sellOffer)]
        );
        require(amount > 0, "No assets to match");
        address buyer = buyOffer.offering;
        address seller = sellOffer.offering;

        consumed[abi.encode(buyOffer)] += amount;
        consumed[abi.encode(sellOffer)] += amount;

        Term memory term = Term(sellOffer.loanToken, sellOffer.collaterals, sellOffer.maturity);
        bytes32 id = _id(term);

        uint256 amountShares = amount.toSharesDown(market[id].totalAssets, market[id].totalShares);

        uint256 repaidShares = Math.min(debtSharesOf[buyer][id], amountShares);
        uint256 boughtShares = amountShares - repaidShares;
        debtSharesOf[buyer][id] -= repaidShares;
        bondSharesOf[buyer][id] += boughtShares;

        uint256 withdrawnShares = Math.min(bondSharesOf[seller][id], amountShares);
        bondSharesOf[seller][id] -= withdrawnShares;
        debtSharesOf[seller][id] += amountShares - withdrawnShares;

        uint256 boughtAmount =
            (boughtShares - withdrawnShares).toAssetsDown(market[id].totalAssets, market[id].totalShares);
        market[id].totalShares += boughtShares - withdrawnShares;
        market[id].totalAssets += boughtAmount;

        require(debtSharesOf[buyer][id] == 0 || _isHealthy(term, buyer), "Buyer is unhealthy");
        require(debtSharesOf[seller][id] == 0 || _isHealthy(term, seller), "Seller is unhealthy");

        uint256 sellerScaledPrice = sellOffer.price * amount / sellOffer.assets;
        uint256 buyerScaledPrice = buyOffer.price * amount / buyOffer.assets;

        uint256 rest;
        if (sellerScaledPrice < buyerScaledPrice) {
            rest = buyerScaledPrice - sellerScaledPrice;
        } else {
            rest = 0;
        }

        IERC20(buyOffer.loanToken).transferFrom(buyer, seller, sellerScaledPrice);
        if (rest > 0) {
            IERC20(buyOffer.loanToken).transferFrom(buyer, msg.sender, rest);
        }
    }

    /// @dev Will revert if there is no withdrawable funds.
    function withdrawBond(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = _id(term);

        uint256 shares = amount.toSharesUp(market[id].totalAssets, market[id].totalShares);

        bondSharesOf[onBehalf][id] -= shares;
        withdrawableShares[id] -= shares;

        market[id].totalShares -= shares;
        market[id].totalAssets -= amount;

        IERC20(term.loanToken).transfer(msg.sender, amount);
    }

    function repayDebt(Term memory term, uint256 amount, address onBehalf) external {
        bytes32 id = _id(term);

        uint256 shares = amount.toSharesDown(market[id].totalAssets, market[id].totalShares);
        debtSharesOf[onBehalf][id] -= shares;
        withdrawableShares[id] += shares;

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), amount);
    }

    function supplyCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] += amount;
        IERC20(collateral).transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(Term memory term, address collateral, uint256 amount, address onBehalf) external {
        collateralOf[onBehalf][_id(term)][collateral] -= amount;

        require(_isHealthy(term, onBehalf), "Unhealthy borrower");

        IERC20(collateral).transfer(msg.sender, amount);
    }

    /// @notice Execute the given collection of `seizures` on the given `term` of the given `borrower`.
    /// @dev On each seizure either `repaidAmounts` or `seizedAssets` should be equal to zero.
    /// @param term The term of the bond.
    /// @param seizures An array of amounts of debt to repay or assets to seize with the index of the collateral in the term's collateral assets.
    /// @param borrower The debtor of the loan.
    /// @param data Arbitrary data to pass to the callback. Pass empty data if not needed.
    /// @return A collection of the actual amounts of debt repaid or asset seized with the collateral index.
    function liquidate(Term memory term, Seizure[] memory seizures, address borrower, bytes calldata data)
        external
        returns (Seizure[] memory)
    {
        require(
            seizures.length <= term.collaterals.length && seizures.length > 0,
            "Cannot seize more assets than the supplied collaterals"
        );

        bytes32 id = _id(term);

        // Over approximation
        uint256 liquidationIncentiveFactor = 1.15e18;

        uint256 totalRepaid;
        uint256 totalCollateralQuoted;
        uint256 maxDebt;

        // Compute the total collateral quoted and borrow capacity.
        for (uint256 i = 0; i < term.collaterals.length; i++) {
            uint256 price = IOracle(term.collaterals[i].oracle).price();
            uint256 collateralQuoted =
                collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
            totalCollateralQuoted += collateralQuoted;
            maxDebt += collateralQuoted.wMulDown(term.collaterals[i].lltv);
        }

        // Check that position is not healthy.
        require(
            debtSharesOf[borrower][id].toAssetsUp(market[id].totalAssets, market[id].totalShares) > maxDebt,
            "Healthy borrower"
        );

        // Compute the repaid and seized amounts by collateral index, remaining collateral and total repaid.
        for (uint256 i = 0; i < seizures.length; i++) {
            require(seizures[i].collateralIndex < term.collaterals.length, "INCONSISTENT_INPUT");
            (uint256 repaidAmount, uint256 seizedAssets, uint256 seizedAssetsQuoted) = _seizeCollateral(
                term.collaterals[seizures[i].collateralIndex], seizures[i], liquidationIncentiveFactor, msg.sender
            );
            seizures[i].repaidAmount = repaidAmount;
            seizures[i].seizedAssets = seizedAssets;
            collateralOf[borrower][_id(term)][term.collaterals[seizures[i].collateralIndex].token] -=
                seizures[i].seizedAssets;
            totalRepaid += seizures[i].repaidAmount;
            totalCollateralQuoted -= seizedAssetsQuoted;
        }

        // Realize bad debt.
        if (totalCollateralQuoted == 0) {
            uint256 debtShares = debtSharesOf[borrower][id];
            market[id].totalAssets -=
                (debtShares.toAssetsUp(market[id].totalAssets, market[id].totalShares) - totalRepaid);
            debtSharesOf[borrower][id] = 0;
        }

        uint256 repaidShares = totalRepaid.toSharesUp(market[id].totalAssets, market[id].totalShares);
        if (totalCollateralQuoted != 0) {
            debtSharesOf[borrower][id] -= repaidShares;
        }
        withdrawableShares[id] += repaidShares;

        // Perform the callback.
        // TODO: simplify with dedicated signature for callback
        if (data.length > 0) {
            bytes memory callbackData = abi.encode(seizures, borrower, msg.sender, data);
            (bool success, bytes memory returnData) = msg.sender.call(callbackData);
            if (!success) lowLevelRevert(returnData);
        }

        IERC20(term.loanToken).transferFrom(msg.sender, address(this), totalRepaid);

        return seizures;
    }

    function bondOf(address owner, bytes32 id) public view returns (uint256) {
        return bondSharesOf[owner][id].toAssetsDown(market[id].totalAssets, market[id].totalShares);
    }

    function debtOf(address owner, bytes32 id) public view returns (uint256) {
        return debtSharesOf[owner][id].toAssetsDown(market[id].totalAssets, market[id].totalShares);
    }

    function withdrawable(bytes32 id) public view returns (uint256) {
        return withdrawableShares[id].toAssetsDown(market[id].totalAssets, market[id].totalShares);
    }

    /// INTERNAL ///

    function _seizeCollateral(Collateral memory c, Seizure memory s, uint256 lif, address liquidator)
        internal
        returns (uint256, uint256, uint256)
    {
        require(exactlyOneZero(s.seizedAssets, s.repaidAmount), "INCONSISTENT_INPUT");
        uint256 collateralPrice = IOracle(c.oracle).price();
        uint256 seizedAssetsQuoted = s.seizedAssets.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        if (s.seizedAssets > 0) {
            s.repaidAmount = seizedAssetsQuoted.wDivUp(lif);
        } else {
            s.seizedAssets = s.repaidAmount.wMulDown(lif).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
            seizedAssetsQuoted = s.seizedAssets.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        }
        IERC20(c.token).transfer(liquidator, s.seizedAssets);
        return (s.repaidAmount, s.seizedAssets, seizedAssetsQuoted);
    }

    // TODO: move to a dedicated library
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }

    function lowLevelRevert(bytes memory returnData) internal pure {
        assembly ("memory-safe") {
            revert(add(32, returnData), mload(returnData))
        }
    }

    function _id(Term memory term) public pure returns (bytes32) {
        return keccak256(abi.encode(term));
    }

    function _checkOffers(
        Offer memory buyOffer,
        Signature memory buySig,
        Offer memory sellOffer,
        Signature memory sellSig
    ) internal view {
        // Check consistency.

        require(buyOffer.buy && !sellOffer.buy, "Inconsistent lend flags");
        require(buyOffer.maturity > block.timestamp, "Buy offer has expired");
        _checkSignature(buyOffer, buySig);
        _checkSignature(sellOffer, sellSig);

        // Check compatibility.

        require(buyOffer.offering != sellOffer.offering, "Same offering");
        require(buyOffer.loanToken == sellOffer.loanToken, "Loan tokens do not match");
        uint256 j = 0;
        for (uint256 i = 0; i < sellOffer.collaterals.length; i++) {
            // Relies on the fact that the collaterals are sorted.
            // Note that we actually never check that.
            // If they are not, the match could fail.
            while (
                bytes20(sellOffer.collaterals[i].token) < bytes20(buyOffer.collaterals[j].token)
                    && j++ < buyOffer.collaterals.length
            ) {}
            require(sellOffer.collaterals[i].token == buyOffer.collaterals[j].token, "Collaterals tokens do not match");
            require(sellOffer.collaterals[i].lltv <= buyOffer.collaterals[j].lltv, "LLTVs do not match");
            require(sellOffer.collaterals[i].oracle == buyOffer.collaterals[j].oracle, "Oracles do not match");
            j++;
        }
        require(buyOffer.maturity == sellOffer.maturity, "Maturities do not match");
        require(buyOffer.price >= sellOffer.price, "Buy offer price is less than sell offer price");
    }

    function _checkSignature(Offer memory offer, Signature memory signature) internal view {
        bytes32 hashStruct = keccak256(abi.encode(OFFER_TYPEHASH, offer));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signatory = ecrecover(digest, signature.v, signature.r, signature.s);

        require(signatory != address(0) && offer.offering == signatory, "Invalid signature");
    }

    function _isHealthy(Term memory term, address borrower) internal view returns (bool) {
        if (term.maturity < block.timestamp) {
            return false;
        } else {
            bytes32 id = _id(Term(term.loanToken, term.collaterals, term.maturity));

            uint256 maxDebt;
            for (uint256 i = 0; i < term.collaterals.length; i++) {
                uint256 price = IOracle(term.collaterals[i].oracle).price();
                uint256 collateralQuoted =
                    collateralOf[borrower][id][term.collaterals[i].token].mulDivDown(price, ORACLE_PRICE_SCALE);
                maxDebt += collateralQuoted.wMulDown(term.collaterals[i].lltv);
            }

            return debtSharesOf[borrower][id].toAssetsUp(market[id].totalAssets, market[id].totalShares) <= maxDebt;
        }
    }
}
