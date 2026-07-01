// Dragon4 (Burger-Dybvig) f64 -> shortest decimal regression test.
// Each value goes through a runtime identity fn so it hits the runtime $__f64_to_str
// helper (not compile-time literal formatting). The test runner strict-compares the
// WASM output against native-TS execution, so any last-digit / notation / sci-threshold
// regression fails the diff. Covers: rounding (0.1+0.2, 7/3), ties, fixed<->scientific
// thresholds in both directions, large/small magnitudes that previously TRAPPED the
// i64-truncation formatter, negatives, and zero.
function id(x: f64): f64 { return x + 0.0; }

console.log(id(0.1 + 0.2));          // 0.30000000000000004
console.log(id(7.0 / 3.0));          // 2.3333333333333335
console.log(id(1.5));
console.log(id(2.5));
console.log(id(0.5));
console.log(id(3.14159));
console.log(id(100.0));
console.log(id(1000000.0));          // 1000000
console.log(id(0.001));
console.log(id(0.0001));
console.log(id(0.0000001));          // 1e-7 (scientific threshold)
console.log(id(0.000001));           // 0.000001 (still fixed)
console.log(id(123456789.5));
console.log(id(123456789012345.6));
console.log(id(1e20));               // 100000000000000000000 (still fixed)
console.log(id(1e21));               // 1e+21 (scientific threshold; formerly TRAPPED)
console.log(id(1e300));              // 1e+300 (formerly TRAPPED)
console.log(id(1.5e-10));            // 1.5e-10
console.log(id(9.999999e-7));
console.log(id(30530260895.884007));
console.log(id(120725452087379.38));
console.log(id(-42.75));
console.log(id(-0.0000003));
console.log(id(0.0));
