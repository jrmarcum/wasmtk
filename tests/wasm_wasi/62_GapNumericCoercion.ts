// deno-fmt-ignore-file
// Compiler-gap regressions (2026-06-30): numeric context-coercion (the emitExpr call-arg / binary-op paths).
// Gap 2  — an f64-returning call truncated by `| 0` in an i32 context.
// Gap 5.0 — an i32 global / TypedArray element passed to an f64 param (needs f64.convert).
// Gap 5.2 — a Float64Array element compared (must use f64.eq, not a truncated i32.eq).
type i32 = number;
type f64 = number;

function getF(x: i32): f64 { return 3.7 + (x as f64); }
let s: i32 = 0;
s = s + (getF(2) | 0);
console.log(s); // 5  (5.7 | 0)

function takeF(x: f64): f64 { return x + 0.5; }
const g: i32 = 5;
const rg: f64 = takeF(g);
console.log(rg); // 5.5   (i32 global → f64 param)
const ia: Int32Array = new Int32Array([10, 20, 30]);
const re: f64 = takeF(ia[2]);
console.log(re); // 30.5  (Int32Array elem → f64 param)

function cmp(a: Float64Array, i: i32, j: i32): i32 { if (a[i] === a[j]) { return 1; } return 0; }
const fa: Float64Array = new Float64Array([1.5, 1.9, 1.5]);
console.log(cmp(fa, 0, 1)); // 0  (1.5 !== 1.9 — must NOT truncate to 1===1)
console.log(cmp(fa, 0, 2)); // 1  (1.5 === 1.5)
