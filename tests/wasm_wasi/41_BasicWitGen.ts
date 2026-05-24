// Phase 41: basic WIT generation — exports become WIT export declarations.
// deno-lint-ignore-file
type i32 = number;
type f64 = number;

export function add(a: i32, b: i32): i32 {
  return a + b;
}

export function multiply(a: f64, b: f64): f64 {
  return a * b;
}

export function square(x: i32): i32 {
  return x * x;
}

console.log(add(3, 4));
