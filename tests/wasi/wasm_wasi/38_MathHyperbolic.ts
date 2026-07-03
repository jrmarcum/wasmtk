// Phase 38 — Hyperbolic: sinh, cosh, tanh, asinh, acosh, atanh
type f64 = number;

// --- sinh ---
console.log(Math.sinh(0));                                  // 0
console.log(Math.round(Math.sinh(1) * 10000));              // 11752 (≈ 1.1752)
console.log(Math.round(Math.sinh(-1) * 10000));             // -11752

// --- cosh ---
console.log(Math.round(Math.cosh(0)));                      // 1
console.log(Math.round(Math.cosh(1) * 10000));              // 15431 (≈ 1.5431)
console.log(Math.round(Math.cosh(-1) * 10000));             // 15431 (even function)

// --- tanh ---
console.log(Math.tanh(0));                                  // 0
console.log(Math.round(Math.tanh(1) * 10000));              // 7616  (≈ 0.7616)
console.log(Math.round(Math.tanh(-1) * 10000));             // -7616

// --- asinh ---
console.log(Math.asinh(0));                                 // 0
console.log(Math.round(Math.asinh(1) * 10000));             // 8814  (≈ 0.8814)
console.log(Math.round(Math.asinh(-1) * 10000));            // -8814

// --- acosh ---
console.log(Math.acosh(1));                                 // 0
console.log(Math.round(Math.acosh(2) * 10000));             // 13170 (≈ 1.317)

// --- atanh ---
console.log(Math.atanh(0));                                 // 0
console.log(Math.round(Math.atanh(0.5) * 10000));           // 5493  (≈ 0.5493)
console.log(Math.round(Math.atanh(-0.5) * 10000));          // -5493
