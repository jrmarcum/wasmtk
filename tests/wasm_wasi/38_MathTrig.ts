// Phase 38 — Trig: sin, cos, tan, atan, atan2, asin, acos
type f64 = number;

// --- sin ---
console.log(Math.sin(0));                                   // 0
console.log(Math.round(Math.sin(Math.PI / 2)));             // 1
console.log(Math.round(Math.sin(-Math.PI / 2)));            // -1
console.log(Math.round(Math.sin(Math.PI / 6) * 100));       // 50  (≈ 0.5)
console.log(Math.round(Math.sin(Math.PI / 4) * 1000));      // 707 (≈ √2/2)

// --- cos ---
console.log(Math.cos(0));                                   // 1
console.log(Math.round(Math.cos(Math.PI)));                 // -1
console.log(Math.round(Math.cos(Math.PI / 3) * 100));       // 50  (≈ 0.5)
console.log(Math.round(Math.cos(Math.PI / 4) * 1000));      // 707 (≈ √2/2)

// --- tan ---
console.log(Math.tan(0));                                   // 0
console.log(Math.round(Math.tan(Math.PI / 4)));             // 1
console.log(Math.round(Math.tan(Math.PI / 6) * 1000));      // 577 (≈ 1/√3)

// --- atan ---
console.log(Math.round(Math.atan(0)));                      // 0
console.log(Math.round(Math.atan(1) * 10000));              // 7854 (≈ π/4)
console.log(Math.round(Math.atan(-1) * 10000));             // -7854

// --- atan2 ---
console.log(Math.round(Math.atan2(1, 1) * 10000));          // 7854 (≈ π/4)
console.log(Math.round(Math.atan2(0, -1) * 10000));         // 31416 (≈ π)
console.log(Math.round(Math.atan2(-1, 0) * 10000));         // -15708 (≈ -π/2)

// --- asin ---
console.log(Math.asin(0));                                  // 0
console.log(Math.round(Math.asin(1) * 10000));              // 15708 (≈ π/2)
console.log(Math.round(Math.asin(0.5) * 10000));            // 5236  (≈ π/6)

// --- acos ---
console.log(Math.acos(1));                                  // 0
console.log(Math.round(Math.acos(0) * 10000));              // 15708 (≈ π/2)
console.log(Math.round(Math.acos(-1) * 10000));             // 31416 (≈ π)
