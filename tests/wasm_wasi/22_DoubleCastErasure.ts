// Phase 22 regression — `expr as unknown as T` double-cast idiom (brief §7a).
// `as unknown` / `as any` are pure type erasure and must emit NO runtime conversion.
// Previously the intermediate `as unknown` reached mapType("unknown") (→ f64) and
// injected a stray `f64.convert_i32_s` on the return path, producing a `(result i32)`
// function whose body left an f64 on the stack: "type error in return[0] (expected i32,
// got f64)". The fix strips erasure casts up front so `x as unknown as T` reduces to
// `x as T`.

function identI32(n: i32): i32 {
  // Return an i32 through the double-cast idiom (the pointer-handle pattern the Tier-1
  // stdlib libraries will use for pointer-typed returns).
  return n as unknown as i32;
}

function identF64(x: f64): f64 {
  // Same idiom on an f64 — must not gain a convert/truncate either.
  return x as unknown as f64;
}

function passThroughAny(n: i32): i32 {
  // `as any` erasure variant.
  return n as any as i32;
}

export function _start(): void {
  const a: i32 = identI32(7);
  console.log("a:", a);                       // 7

  const b: i32 = 42 as unknown as i32;         // inline double cast
  console.log("b:", b);                       // 42

  const c: f64 = identF64(3.5);
  console.log("c:", c);                       // 3.5

  const d: i32 = passThroughAny(99);
  console.log("d:", d);                       // 99

  // Single `as unknown` (no trailing cast) reduces to the bare expression.
  const e: i32 = 5 as unknown;
  console.log("e:", e);                       // 5
}

_start();
