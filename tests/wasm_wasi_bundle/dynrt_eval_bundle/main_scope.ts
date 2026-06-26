// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.7: lexical BLOCK SCOPING in eval
// source. Each `{ }` block / `for` loop / `catch` runs in a fresh child scope, so `let`/`const` declared
// inside it do not leak; bare assignment `x = v` walks the scope chain to update the DECLARING scope
// (not a shadow); the `catch (e)` binding is scoped to the catch.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the scoping rules. The probe idiom
// `+ (typeof v === "undefined" ? 100 : 0)` proves a name is GONE outside its block.

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

// ── block scoping: let/const don't leak ──────────────────────────────────────────────────────────
checkRun("let total = 0; { let x = 5; total = total + x; } total = total + (typeof x === \"undefined\" ? 100 : 0); return total;", 105);
checkRun("let r = 0; if (1 === 1) { let v = 8; r = v; } r = r + (typeof v === \"undefined\" ? 100 : 0); return r;", 108);

// ── shadowing: inner let shadows, outer unchanged ────────────────────────────────────────────────
checkRun("let x = 10; { let x = 20; } return x;", 10);
checkRun("let x = 1; { let x = 2; x = 3; } return x;", 1); // inner reassign hits the inner x only

// ── assignment from inner block updates the OUTER declaring scope ─────────────────────────────────
checkRun("let r = 1; { r = 2; } return r;", 2);
checkRun("let count = 0; { count += 5; let temp = 99; } return count;", 5); // temp gone, count updated
checkRun("let a = 0; { let b = 1; { let c = 2; a = a + b + c; } } return a;", 3); // nested blocks

// ── for-loop variable scoped to the loop ─────────────────────────────────────────────────────────
checkRun("let sum = 0; for (let i = 0; i < 4; i++) { sum = sum + i; } sum = sum + (typeof i === \"undefined\" ? 100 : 0); return sum;", 106);
checkRun("let sum = 0; for (let i = 0; i < 3; i++) { let d = i * 2; sum = sum + d; } return sum;", 6); // body let per-iter
checkRun("let acc = 0; for (const v of [3, 4, 5]) { acc = acc + v; } return acc;", 12);

// ── while body block scoping + outer mutation ────────────────────────────────────────────────────
checkRun("let sum = 0; let i = 0; while (i < 3) { let step = i + 1; sum = sum + step; i = i + 1; } return sum;", 6);

// ── fresh catch scope ────────────────────────────────────────────────────────────────────────────
checkRun("let r = 0; try { throw 7; } catch (e) { r = e; } r = r + (typeof e === \"undefined\" ? 100 : 0); return r;", 107);
checkRun("let e = 1; try { throw 9; } catch (e) { } return e;", 1); // catch e shadows; outer e unchanged
checkRun("let outer = 5; try { throw 2; } catch (err) { outer = outer + err; } return outer;", 7); // catch updates outer

console.log("dynrt 2e.7 block scoping: all checks passed");
