// Regression: array-element arithmetic inside console.log (`console.log("x:", arr[i] + arr[j])`).
// The greedy `arr[idx]` regex in parseSingleArg/exprToWat used to capture `0] + arr[1` as the index
// and emit a single mangled access, dropping the rest of the sum. Now the index is bracket-balance
// guarded so the expression falls through to the binary-op loop, which infers the element type from
// the array (i32[] → i32.add, f64[] → f64.add).

type i32 = number;
type f64 = number;

const ints: i32[] = [10, 20, 30, 40];
const flts: f64[] = [1.5, 2.5, 4.0];

console.log("two:", ints[0] + ints[1]); // two: 30
console.log("three:", ints[0] + ints[1] + ints[2]); // three: 60
console.log("sub:", ints[3] - ints[0]); // sub: 30
console.log("mul:", ints[1] * ints[0]); // mul: 200
console.log("f64:", flts[0] + flts[1] + flts[2]); // f64: 8
console.log("single:", ints[2]); // single: 30 (single element still works)
console.log("mixed:", ints[0] + ints[1] * 2); // mixed: 50
