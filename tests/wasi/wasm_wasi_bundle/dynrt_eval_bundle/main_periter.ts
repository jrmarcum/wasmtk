// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.7a: PER-ITERATION `let` binding.
// `for (let i …)` / `for (const x of …)` give each iteration a FRESH binding of the loop variable, so a
// closure created in the body captures THAT iteration's value (`0,1,2`), not the single shared/final
// value (`3,3,3`). `var` deliberately stays a SINGLE shared binding (ES5/var semantics — the distinction
// the 2e.7b var-gate will police). Closures are stored via `fns[i] = …` (dynArrSet appends when i===len,
// so it works without a `.push` method) and called after the loop with `fns[k]()`.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves per-iteration capture.

type i32 = number;
type f64 = number;

import { dynNumberValue, dynObject, dynRun, dynTypeof } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

function checkRun(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0); // result must be a number
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── classic for: per-iteration capture (0,1,2 — NOT 3,3,3) ───────────────────────────────────────
checkRun("let fns = []; for (let i = 0; i < 3; i++) { fns[i] = () => i; } return fns[0]() + fns[1]() * 10 + fns[2]() * 100;", 210);
checkRun("let fns = []; for (let i = 1; i <= 3; i++) { fns[i - 1] = () => i * i; } return fns[0]() + fns[1]() + fns[2]();", 14);

// ── normal accumulation still works (loop var carries across iterations via the per-iteration copy) ─
checkRun("let sum = 0; for (let i = 0; i < 5; i++) { sum = sum + i; } return sum;", 10);

// ── body-declared `let` per-iteration AND loop var per-iteration together ─────────────────────────
checkRun("let fns = []; for (let i = 0; i < 3; i++) { let d = i * 2; fns[i] = () => d; } return fns[0]() + fns[1]() * 10 + fns[2]() * 100;", 420);

// ── continue: skipped iterations don't capture; survivors keep their own value ────────────────────
checkRun("let fns = []; let k = 0; for (let i = 0; i < 4; i++) { if (i === 1) { continue; } fns[k] = () => i; k = k + 1; } return fns[0]() + fns[1]() * 10 + fns[2]() * 100;", 320);

// ── for-of: per-iteration capture of the element ─────────────────────────────────────────────────
checkRun("let fns = []; let k = 0; for (const x of [10, 20, 30]) { fns[k] = () => x; k = k + 1; } return fns[0]() + fns[1]() * 10 + fns[2]() * 100;", 3210);

// ── `var` stays SHARED (single binding) — all closures see the final value (3,3,3 → 9) ────────────
checkRun("let fns = []; for (var i = 0; i < 3; i++) { fns[i] = () => i; } return fns[0]() + fns[1]() + fns[2]();", 9);

console.log("dynrt 2e.7a per-iteration let: all checks passed");
