// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function getBit(uint256 bitmap, uint256 bit) external returns (bool) envfree;
    function setBit(uint256 bitmap, uint256 bit) external returns (uint256) envfree;
    function toggleBit(uint256 bitmap, uint256 bit) external returns (uint256) envfree;
    function clearBit(uint256 bitmap, uint256 bit) external returns (uint256) envfree;
    function msb(uint256 bitmap) external returns (uint256) envfree;
}

/// RULES ///

rule zeroBitmapEmpty(uint256 bit) {
    bool isBitSet = getBit(0, bit);
    assert !isBitSet, "zero bitmap has no bit set";
}

rule setBitSetsBit(uint256 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 256, "bitmap functions only work for bit < 256";
    require otherBit < 256, "bit in range 0..255";

    bool otherBefore = getBit(bitmap, otherBit);

    uint256 bitmapAfter = setBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);

    assert bitAfter, "setBit sets the bit";
    assert otherBit != bit => otherBefore == otherAfter, "setBit doesn't change other bits";
}

rule clearBitClearsBit(uint256 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 256, "bitmap functions only work for bit < 256";
    require otherBit < 256, "bit in range 0..255";

    bool otherBefore = getBit(bitmap, otherBit);

    uint256 bitmapAfter = clearBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);

    assert !bitAfter, "clearBit clears the bit";
    assert otherBit != bit => otherBefore == otherAfter, "clearBit doesn't change other bits";
}

rule toggleBitTogglesBit(uint256 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 256, "bitmap functions only work for bit < 256";
    require otherBit < 256, "bit in range 0..255";

    bool otherBefore = getBit(bitmap, otherBit);
    bool bitBefore = getBit(bitmap, bit);

    uint256 bitmapAfter = toggleBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);

    assert bitBefore != bitAfter, "toggleBit toggles the bit";
    assert otherBit != bit => otherBefore == otherAfter, "toggleBit doesn't change other bits";
}

rule msb(uint256 bitmap) {
    uint256 msbBit = msb(bitmap);
    uint256 otherBit;

    assert bitmap == 0 => msbBit == 2 ^ 256 - 1;
    assert bitmap != 0 => msbBit < 256;
    assert bitmap != 0 => getBit(bitmap, msbBit);
    assert bitmap != 0 && otherBit < 256 && getBit(bitmap, otherBit) => otherBit <= msbBit;
}

rule setBitFitsUint128(uint128 bitmap, uint256 bit) {
    require bit < 128, "precondition";
    uint256 bitmapAfter = setBit(bitmap, bit);

    assert bitmapAfter < 2 ^ 128, "postcondition: bitmap fits in uint128";
}

rule clearBitFitsUint128(uint128 bitmap, uint256 bit) {
    require bit < 128, "precondition";
    uint256 bitmapAfter = clearBit(bitmap, bit);

    assert bitmapAfter < 2 ^ 128, "postcondition: bitmap fits in uint128";
}

rule toggleBitFitsUint128(uint128 bitmap, uint256 bit) {
    require bit < 128, "precondition";
    uint256 bitmapAfter = toggleBit(bitmap, bit);

    assert bitmapAfter < 2 ^ 128, "postcondition: bitmap fits in uint128";
}
