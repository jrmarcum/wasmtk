// #14.3.4 — hybrid --auto routes a function with a DYNAMIC body to the wasic+dynrt core.
//
// `evalScaled` has a fully-typed signature (f64 → f64) so it marshals to the host normally, but its
// BODY uses `eval` + an `any` value — which now lower to the merged dynrt runtime (increments
// 3.1–3.3). Before 14.3 this function would have failed to compile in the core; now it routes to
// WASM. `double` is a plain static function that routes as before. If a dynamic body had used a
// feature wasic+dynrt can't compile, the try-compile/fall-back-to-host ladder would keep that one
// function in the TS host instead of failing the whole build.
//
// Verify manually:
//   wasmtk hybrid --auto tests/hybrid_fixtures/dynamic_hybrid.ts
//   deno run --allow-read tests/hybrid_fixtures/dynamic_hybrid_runner.ts
//   → evalScaled(8) = 50
//     double(21) = 42

export function evalScaled(n: f64): f64 {
  const base: any = eval("6 * 7"); // 42, computed by the dynrt evaluator
  const scaled: any = base + n; // dynamic addition (any + f64)
  return scaled as f64; // unbox the result back to f64
}

export function double(x: f64): f64 {
  return x * 2;
}

const a: f64 = evalScaled(8); // 42 + 8 = 50
const b: f64 = double(21); // 42
console.log("evalScaled(8) =", a);
console.log("double(21) =", b);
