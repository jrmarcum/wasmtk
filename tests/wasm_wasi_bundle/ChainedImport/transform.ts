import { SCALE, OFFSET } from "./constants.ts";

type i32 = number;

// Mid-layer module — uses constants from its own import
export function scale(x: i32): i32 {
  return x * SCALE;
}

export function shift(x: i32): i32 {
  return x + OFFSET;
}
