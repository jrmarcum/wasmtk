// Phase 38 — Exp/Log: exp, log, log2, log10, cbrt, expm1, log1p
type f64 = number;

// --- exp ---
console.log(Math.exp(0));                                   // 1
console.log(Math.round(Math.exp(1) * 1000));                // 2718 (≈ e)
console.log(Math.round(Math.exp(2) * 1000));                // 7389 (≈ e²)
console.log(Math.round(Math.exp(-1) * 10000));              // 3679 (≈ 1/e)

// --- log (natural log) ---
console.log(Math.log(1));                                   // 0
console.log(Math.round(Math.log(Math.E) * 1000));           // 1000 (≈ 1)
console.log(Math.round(Math.log(Math.E * Math.E) * 1000));  // 2000 (≈ 2)
console.log(Math.round(Math.log(10) * 10000));              // 23026 (≈ ln10)

// --- log2 ---
console.log(Math.round(Math.log2(1)));                      // 0
console.log(Math.round(Math.log2(2)));                      // 1
console.log(Math.round(Math.log2(8)));                      // 3
console.log(Math.round(Math.log2(1024)));                   // 10

// --- log10 ---
console.log(Math.round(Math.log10(1)));                     // 0
console.log(Math.round(Math.log10(10)));                    // 1
console.log(Math.round(Math.log10(1000)));                  // 3

// --- cbrt ---
console.log(Math.cbrt(0));                                  // 0
console.log(Math.round(Math.cbrt(1)));                      // 1
console.log(Math.round(Math.cbrt(8)));                      // 2
console.log(Math.round(Math.cbrt(27)));                     // 3
console.log(Math.round(Math.cbrt(-8)));                     // -2

// --- expm1 ---
console.log(Math.expm1(0));                                 // 0
console.log(Math.round(Math.expm1(1) * 1000));              // 1718 (≈ e-1)

// --- log1p ---
console.log(Math.log1p(0));                                 // 0
console.log(Math.round(Math.log1p(1) * 10000));             // 6931 (≈ ln2)
