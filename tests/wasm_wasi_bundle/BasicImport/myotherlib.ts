type i32 = number;

// Deliberately uses the same function name "add" as mathlib.ts to prove
// that module-prefix mangling prevents a WAT name collision.
export function add(a: i32, b: i32): i32 {
  return a * 10 + b; // different behaviour — not a true sum
}

export function negate(a: i32): i32 {
  return 0 - a;
}
