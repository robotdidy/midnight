// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;

    function UtilsLib.getBit(uint256 bitmap, uint256 bit) internal returns (bool) => summaryGetBit(bitmap, bit);
    function UtilsLib.setBit(uint256 bitmap, uint256 bit) internal returns (uint256) => summarySetBit(bitmap, bit);
    function UtilsLib.toggleBit(uint256 bitmap, uint256 bit) internal returns (uint256) => summaryToggleBit(bitmap, bit);
    function UtilsLib.clearBit(uint256 bitmap, uint256 bit) internal returns (uint256) => summaryClearBit(bitmap, bit);
    function UtilsLib.msb(uint256 bitmap) internal returns (uint256) => summaryMsb(bitmap);

    // Summarize internals irrelevant to the properties.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
}

/// SUMMARIES ///

persistent ghost summaryGetBit(uint256, uint256) returns bool {
    // see rule zeroBitmapEmpty in Bitmap.spec
    axiom forall uint256 bit. !summaryGetBit(0, bit);
}

function summarySetBit(uint256 bitmap, uint256 bit) returns (uint256) {
    uint256 result;
    assert bitmap < 2 ^ 128;
    assert bit < 128;
    require summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherbit. otherbit != bit && otherbit < 128 => summaryGetBit(result, otherbit) == summaryGetBit(bitmap, otherbit), "see Bitmap.spec";
    require result < 2 ^ 128, "fits in uint128";
    return result;
}

function summaryClearBit(uint256 bitmap, uint256 bit) returns (uint256) {
    uint256 result;
    assert bitmap < 2 ^ 128;
    assert bit < 128;
    require !summaryGetBit(result, bit), "see Bitmap.spec";
    require forall uint256 otherbit. otherbit != bit && otherbit < 128 => summaryGetBit(result, otherbit) == summaryGetBit(bitmap, otherbit), "see Bitmap.spec";
    require result < 2 ^ 128, "fits in uint128";
    return result;
}

function summaryToggleBit(uint256 bitmap, uint256 bit) returns (uint256) {
    uint256 result;
    assert bitmap < 2 ^ 128;
    assert bit < 128;
    require summaryGetBit(result, bit) != summaryGetBit(bitmap, bit), "see Bitmap.spec";
    require forall uint256 otherbit. otherbit != bit && otherbit < 128 => summaryGetBit(result, otherbit) == summaryGetBit(bitmap, otherbit), "see Bitmap.spec";
    require result < 2 ^ 128, "fits in uint128";
    return result;
}

function summaryMsb(uint256 bitmap) returns (uint256) {
    uint256 bit;
    assert bitmap < 2 ^ 128 && bitmap != 0;

    require bit < 128, "see Bitmap.spec";
    require summaryGetBit(bitmap, bit), "see Bitmap.spec";
    require forall uint256 otherbit. otherbit < 256 && summaryGetBit(bitmap, otherbit) => otherbit <= bit, "see Bitmap.spec";
    return bit;
}

strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateralOf(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].activatedCollaterals, collateralIndex));
