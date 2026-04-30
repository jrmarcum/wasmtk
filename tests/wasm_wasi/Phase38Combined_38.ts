// Phase 38 — Combined: all extended Math functions together
type f64 = number;
type i32 = number;

// Pythagorean identity: sin²(x) + cos²(x) = 1
const angle: f64 = Math.PI / 5;
const identity: f64 = Math.sin(angle) * Math.sin(angle) + Math.cos(angle) * Math.cos(angle);
console.log(Math.round(identity));                          // 1

// tan = sin/cos
const a: f64 = Math.PI / 7;
const tanDirect: f64 = Math.tan(a);
const tanRatio: f64 = Math.sin(a) / Math.cos(a);
console.log(Math.round((tanDirect - tanRatio) * 1e12));     // 0 (equal to 12 decimal places)

// exp/log inverses: log(exp(x)) = x
const x: f64 = 2.5;
console.log(Math.round(Math.log(Math.exp(x)) * 1000));      // 2500

// log2 / log10 relationship
console.log(Math.round(Math.log2(100)));                    // 7  (≈ 6.644)
console.log(Math.round(Math.log10(100)));                   // 2

// cbrt(x)³ = x
const cb: f64 = Math.cbrt(125);
console.log(Math.round(cb));                                // 5
console.log(Math.round(cb * cb * cb));                      // 125

// Hyperbolic identity: cosh²(x) - sinh²(x) = 1
const hx: f64 = 1.3;
const hid: f64 = Math.cosh(hx) * Math.cosh(hx) - Math.sinh(hx) * Math.sinh(hx);
console.log(Math.round(hid));                               // 1

// tanh in range (-1, 1)
const t: f64 = Math.tanh(3.0);
console.log(t > 0 && t < 1 ? 1 : 0);                      // 1

// asin/acos complementary: asin(x) + acos(x) = π/2
const v: f64 = 0.6;
const comp: f64 = Math.asin(v) + Math.acos(v);
console.log(Math.round(comp * 10000));                      // 15708 (≈ π/2)

// atan2 quadrant check
console.log(Math.round(Math.atan2(0, 1) * 1000));           // 0      (east)
console.log(Math.round(Math.atan2(1, 0) * 10000));          // 15708  (north = π/2)

// expm1 and log1p accuracy for small value
console.log(Math.round(Math.expm1(0) * 1000));              // 0
console.log(Math.round(Math.log1p(0) * 1000));              // 0

// random in [0, 1)
const r: f64 = Math.random();
console.log(r >= 0 && r < 1 ? 1 : 0);                     // 1
