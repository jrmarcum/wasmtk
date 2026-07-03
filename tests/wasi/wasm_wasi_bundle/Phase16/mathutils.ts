// Phase 16 helper library — own exports + named re-export from lib.ts
export function double(x: i32): i32 {
  return x * 2;
}

export function triple(x: i32): i32 {
  return x * 3;
}

// Named re-export: bubble lib.ts's `square` out of this module.
export { square } from "./lib.ts";
