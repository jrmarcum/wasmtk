// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.2: literals in eval source.
// Array `[…]`, object `{…}` (incl. "quoted"/shorthand keys), and template `` `…${expr}…` `` literals
// are now built by the interpreter (parsePrimary), so dynamic code can construct values inline — and
// `for…of` over an INLINE array literal now works (the 2e.1 deferred case).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the literal forms.

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

// run a program in a FRESH plain env; assert numeric result
function checkRun(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── array literals ───────────────────────────────────────────────────────────────────────────────
checkRun("const a = [10, 20, 30]; return a[1];", 20);
checkRun("const a = [10, 20, 30]; return a.length;", 3);
checkRun("const a = []; return a.length;", 0); // empty
checkRun("const a = [1, 2, 3, 4, 5]; let s = 0; for (const x of a) { s = s + x; } return s;", 15);
checkRun("let s = 0; for (const x of [2, 4, 6]) { s = s + x; } return s;", 12); // INLINE literal in for-of
checkRun("const m = [[1, 2], [3, 4]]; return m[1][0] + m[0][1];", 5); // nested: 3 + 2
checkRun("const a = [5, 10, 15]; let s = 0; for (const x of a) { if (x === 10) { continue; } s = s + x; } return s;", 20);

// ── object literals ──────────────────────────────────────────────────────────────────────────────
checkRun("const o = {x: 5, y: 7}; return o.x + o.y;", 12);
checkRun('const o = {a: 1, b: 2, c: 3}; return o["b"];', 2); // string index
checkRun("let x = 9; const o = {x}; return o.x;", 9); // shorthand
checkRun("const o = {pt: {a: 3, b: 4}}; return o.pt.a + o.pt.b;", 7); // nested object
checkRun("const o = {vals: [10, 20, 30]}; return o.vals[2];", 30); // object holding an array

// ── template literals (verified via .length and ===) ─────────────────────────────────────────────
checkRun("const t = `ab${1 + 2}cd`; return t.length;", 5); // "ab3cd"
checkRun("const x = 5; const t = `n${x}n`; return t.length;", 3); // "n5n"
checkRun("const t = `${10 + 5}`; return t.length;", 2); // "15"
checkRun('const x = 7; const t = `v${x}`; return (t === "v7") ? 1 : 0;', 1);

console.log("dynrt 2e.2 literals: all checks passed");
