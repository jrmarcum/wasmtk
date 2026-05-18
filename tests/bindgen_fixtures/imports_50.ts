// bindgen_imports_50: module with external (Phase 40) imports — for bindgen import-section test
// Method names use simple snake_case to survive the kebab-case round-trip cleanly.
// deno-lint-ignore-file
type f64 = number;
type i32 = number;

declare const env: {
  mul(a: f64, b: f64): f64;
  add(a: i32, b: i32): i32;
};

export function scale(x: f64, factor: f64): f64 {
  return env.mul(x, factor);
}

export function combine(a: i32, b: i32): i32 {
  return env.add(a, b);
}
