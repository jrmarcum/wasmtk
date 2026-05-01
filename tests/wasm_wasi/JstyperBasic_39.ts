// Phase 39 — jstyper basic output: i32 arithmetic
// Represents typed .ts produced by: wasmtk jstyper basicmath.js
// (basicmath.d.ts declares add/square as i32, multiply as f64)
type i32 = number;
type f64 = number;

export function add(a: i32, b: i32): i32 {
  return a + b;
}

export function multiply(a: f64, b: f64): f64 {
  return a * b;
}

export function square(a: i32): i32 {
  return a * a;
}

console.log(add(3, 4));        // 7
console.log(multiply(6.0, 7.0)); // 42
console.log(square(5));        // 25
