// Phase 41: combined — multiple exports + Phase 40 imports → complete WIT world.
// deno-lint-ignore-file
type i32 = number;
type f64 = number;
type bool = boolean;

declare interface Allocator {
  alloc(size: i32): i32;
  free(ptr: i32): void;
}

declare const allocator: Allocator;

export function allocate(size: i32): i32 {
  return allocator.alloc(size);
}

export function release(ptr: i32): void {
  allocator.free(ptr);
}

export function clamp(val: f64, lo: f64, hi: f64): f64 {
  if (val < lo) return lo;
  if (val > hi) return hi;
  return val;
}

export function isPositive(x: i32): bool {
  return x > 0;
}

console.log(55);
