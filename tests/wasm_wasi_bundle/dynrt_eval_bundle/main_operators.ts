// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.5: operators. `typeof`, nullish
// coalescing `??`, optional chaining `?.` (member / index, with short-circuit), and array spread
// `[...a, ...b]` in eval source.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the operators.

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

// ── typeof ───────────────────────────────────────────────────────────────────────────────────────
checkRun("return (typeof 5 === \"number\") ? 1 : 0;", 1);
checkRun("return (typeof \"hi\" === \"string\") ? 1 : 0;", 1);
checkRun("return (typeof true === \"boolean\") ? 1 : 0;", 1);
checkRun("const o = {}; return (typeof o === \"object\") ? 1 : 0;", 1);
checkRun("const f = () => 1; return (typeof f === \"function\") ? 1 : 0;", 1);
checkRun("return (typeof undefined === \"undefined\") ? 1 : 0;", 1);
checkRun("const x = 5; return (typeof x === \"number\") ? 100 : 0;", 100);

// ── nullish coalescing ?? (note: 0 / false are NOT nullish, unlike ||) ─────────────────────────────
checkRun("return null ?? 5;", 5);
checkRun("return 3 ?? 5;", 3);
checkRun("return 0 ?? 5;", 0); // 0 is not nullish
checkRun("const o = {x: 0}; return o.x ?? 99;", 0);
checkRun("const o = {}; return o.missing ?? 99;", 99); // missing → undefined → nullish

// ── optional chaining ?. ───────────────────────────────────────────────────────────────────────────
checkRun("const o = {x: {y: 7}}; return o?.x?.y;", 7);
checkRun("const o = null; return o?.x ?? -1;", -1);
checkRun("const o = {a: 5}; return o?.b?.c ?? -2;", -2); // o.b undefined → short-circuit
checkRun("const o = {arr: [10, 20, 30]}; return o?.arr?.[1];", 20);
checkRun("const o = {f: () => 42}; return o?.f();", 42); // ?.f then a regular ()
checkRun("const o = null; return (o?.f() ?? -3);", -3); // optDead propagates through the call

// ── array spread ───────────────────────────────────────────────────────────────────────────────────
checkRun("const a = [1, 2]; const b = [...a, 3, 4]; return b[0] + b[1] + b[2] + b[3];", 10);
checkRun("const a = [1, 2]; const c = [...a, ...a]; return c.length;", 4);
checkRun("const a = [5]; const b = [0, ...a, 9]; return b[1];", 5);
checkRun("const a = [10, 20]; let s = 0; for (const x of [...a, 30]) { s = s + x; } return s;", 60);

console.log("dynrt 2e.5 operators: all checks passed");
