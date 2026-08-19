// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Shared functionality used by multiple classes and their implementations.

int validateRadix(int radix) =>
    RangeError.checkValueInInterval(radix, 2, 36, 'radix');

/// Converts radix digits into their numeric values.
///
/// Converts the characters `0`-`9` into the values 0 through 9,
/// and the letters `a`-`z` or `A`-`Z` into values 10 through 35,
/// and return that value.
/// Any other character returns a value above 35, which means it's
/// not a valid digit in any radix in the range 2 through 36.
int decodeDigit(int c) {
  // Hex digit char codes
  const c0 = 48; // '0'.codeUnitAt(0)
  const ca = 97; // 'a'.codeUnitAt(0)

  var digit = c ^ c0;
  if (digit < 10) return digit;
  var letter = (c | 0x20) - ca;
  if (letter >= 0) {
    // Returns values above 36 for invalid digits.
    // The value is checked against the actual radix where the return
    // value is used, so this is safe.
    return letter + 10;
  } else {
    return 255; // Never a valid radix.
  }
}

// Assumes i is <= 32-bit
int numberOfLeadingZeros(int i) {
  i |= i >> 1;
  i |= i >> 2;
  i |= i >> 4;
  i |= i >> 8;
  i |= i >> 16;
  return bitCount(~i);
}

int numberOfTrailingZeros(int i) => bitCount((i & -i) - 1);

// Assumes i is <= 32-bit.
int bitCount(int i) {
  // See "Hacker's Delight", section 5-1, "Counting 1-Bits".

  // The basic strategy is to use "divide and conquer" to
  // add pairs (then quads, etc.) of bits together to obtain
  // sub-counts.
  //
  // A straightforward approach would look like:
  //
  // i = (i & 0x55555555) + ((i >>  1) & 0x55555555);
  // i = (i & 0x33333333) + ((i >>  2) & 0x33333333);
  // i = (i & 0x0F0F0F0F) + ((i >>  4) & 0x0F0F0F0F);
  // i = (i & 0x00FF00FF) + ((i >>  8) & 0x00FF00FF);
  // i = (i & 0x0000FFFF) + ((i >> 16) & 0x0000FFFF);
  //
  // The code below removes unnecessary &'s and uses a
  // trick to remove one instruction in the first line.

  i -= (i >> 1) & 0x55555555;
  i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
  i = (i + (i >> 4)) & 0x0F0F0F0F;
  i += i >> 8;
  i += i >> 16;
  return i & 0x0000003F;
}
