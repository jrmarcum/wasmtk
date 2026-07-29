// Regression: `*`, `/` and `%` share one precedence level and are LEFT-associative, but the
// binary-op loop split at the FIRST operator in table order, and `*` is listed before `/` and `%`.
// So `a * b / c` was parsed as `a * (b / c)` — right-associative. With integer division that is
// silently, badly wrong: 180 * 5 / 9 gave 180 * (5/9) = 0 instead of 100, and 180 * 5 % 9 gave
// 180 * (5%9) = 900 instead of 0. Surfaced by a Phase 29 getter/setter stress test whose
// Fahrenheit→Celsius conversion `(f - 32) * 5 / 9` silently produced 0.
// See design-decisions.md § "Same-precedence operator groups split at the RIGHTMOST operator".

type i32 = number;
type f64 = number;

function toCelsius(f: i32): i32 {
  return (f - 32) * 5 / 9;
}

export function testMultiplicativeAssociativity(): void {
  const a: i32 = 180;

  // The two broken shapes: `*` left of `/` or `%`
  console.log("a * 5 / 9:", a * 5 / 9); // 100  (was 0)
  console.log("a * 5 % 9:", a * 5 % 9); // 0    (was 900)

  // Parenthesised receiver — same bug, different surface
  console.log("(a + 0) * 5 / 9:", (a + 0) * 5 / 9); // 100 (was 0)

  // Shapes that were already correct must stay correct
  console.log("a / 5 * 9:", a / 5 * 9); // 324
  console.log("a / 9 / 2:", a / 9 / 2); // 10
  console.log("a * 5:", a * 5); // 900
  console.log("a / 9:", a / 9); // 20
  console.log("a % 7:", a % 7); // 5
  console.log("a * 2 * 3:", a * 2 * 3); // 1080
  console.log("a % 7 * 2:", a % 7 * 2); // 10

  // Longer chains
  console.log("a * 5 / 9 / 2:", a * 5 / 9 / 2); // 50
  console.log("a * 4 / 8 * 3:", a * 4 / 8 * 3); // 270

  // Mixed with additive (additive binds looser, so grouping must not change)
  console.log("1 + a * 5 / 9:", 1 + a * 5 / 9); // 101
  console.log("a * 5 / 9 - 1:", a * 5 / 9 - 1); // 99

  // Through a function body (the original failing shape)
  console.log("toCelsius(212):", toCelsius(212)); // 100
  console.log("toCelsius(32):", toCelsius(32)); // 0

  // f64 division is unaffected by integer truncation but must still group left
  const x: f64 = 9.0;
  console.log("f64 x * 2.0 / 4.0:", x * 2.0 / 4.0); // 4.5
}

testMultiplicativeAssociativity();
