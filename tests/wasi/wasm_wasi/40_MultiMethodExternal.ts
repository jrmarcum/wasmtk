// Phase 40: external interface with multiple methods of different signatures.
// deno-lint-ignore-file
type i32 = number;
type f64 = number;

declare const ops: {
  add(a: i32, b: i32): i32;
  scale(x: f64, factor: f64): f64;
  negate(x: i32): i32;
};

export function computeAdd(a: i32, b: i32): i32 {
  return ops.add(a, b);
}

export function computeScale(x: f64, factor: f64): f64 {
  return ops.scale(x, factor);
}

export function computeNeg(x: i32): i32 {
  return ops.negate(x);
}

console.log(49);
