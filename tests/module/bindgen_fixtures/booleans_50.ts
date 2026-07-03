// bindgen_bool_50: bool-returning exported functions — compiled to WASM library for bindgen test
// deno-lint-ignore-file
type f64 = number;
type i32 = number;
type bool = boolean;

export function isPositive(x: f64): bool {
  return x > 0.0;
}

export function inRange(v: f64, lo: f64, hi: f64): bool {
  return v >= lo && v <= hi;
}

export function isEven(n: i32): bool {
  return (n % 2) === 0;
}
