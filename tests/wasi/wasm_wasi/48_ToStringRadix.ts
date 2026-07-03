// Regression: n.toString(radix) with a RUNTIME value (and a runtime radix). Previously only the
// literal form (14).toString(2) was constant-folded; a runtime n.toString(2) stubbed to 0. Now a
// $__i32_to_str_radix helper handles base 2..36 across assignment / console.log / template / arg.
type i32 = number;

const n: i32 = 14;
const big: i32 = 255;
const radix: i32 = 16;

console.log(n.toString(2)); // 1110
console.log(big.toString(16)); // ff
console.log(big.toString(radix)); // ff (runtime radix)
console.log(n.toString(8)); // 16
console.log((255).toString(36)); // 73 (literal still folds)

const s: string = big.toString(2);
console.log(s); // 11111111
console.log(`hex=${big.toString(16)}`); // hex=ff

function fmtHex(x: i32): string {
  return x.toString(16);
}
console.log(fmtHex(4095)); // fff

const neg: i32 = -255;
console.log(neg.toString(16)); // -ff
