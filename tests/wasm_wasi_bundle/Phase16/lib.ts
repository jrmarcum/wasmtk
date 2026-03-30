// Phase 16 helper library — named exports + default export
export function square(x: i32): i32 {
  return x * x;
}

export function negate(x: i32): i32 {
  return 0 - x;
}

// Default export: a two-argument adder.
export default function compute(a: i32, b: i32): i32 {
  return a + b;
}
