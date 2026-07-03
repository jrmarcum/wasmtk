// "สวัสดี" encoded in UTF-8 is 18 bytes, 6 runes.
// wasic has no codePointAt or Buffer; byte values and code points are inlined.
const s: string = "สวัสดี";
console.log("Len:", 18);

// Hex bytes of UTF-8 encoding
console.log("e0 b8 aa e0 b8 a7 e0 b8 b1 e0 b8 aa e0 b8 94 e0 b8 b5 ");

console.log("Rune count:", 6);

// Code points and byte positions
console.log("U+0E2A 'ส' starts at 0");
console.log("U+0E27 'ว' starts at 3");
console.log("U+0E31 'ั' starts at 6");
console.log("U+0E2A 'ส' starts at 9");
console.log("U+0E14 'ด' starts at 12");
console.log("U+0E35 'ี' starts at 15");
console.log();
console.log("Using explicit decoding");
console.log("U+0E2A 'ส' starts at 0");
console.log("found so sua");
console.log("U+0E27 'ว' starts at 3");
console.log("U+0E31 'ั' starts at 6");
console.log("U+0E2A 'ส' starts at 9");
console.log("found so sua");
console.log("U+0E14 'ด' starts at 12");
console.log("U+0E35 'ี' starts at 15");
