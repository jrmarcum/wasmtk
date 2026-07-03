// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.4: member / index assignment.
// `o.x = v`, `o[k] = v`, `arr[i] = v` (plain and `+=`/`-=`/`*=`/`/=` compound), nested targets, and
// computed keys — so dynamic code can MUTATE objects and arrays in place.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the assignment forms.

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
  check(dynTypeof(r) === 3 ? 1 : 0);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── object member assignment ─────────────────────────────────────────────────────────────────────
checkRun("const o = {x: 1, y: 2}; o.x = 10; return o.x;", 10);
checkRun("const o = {x: 1}; o.x = o.x + 5; return o.x;", 6);
checkRun("const o = {}; o.a = 7; return o.a;", 7); // new property on empty object
checkRun("const o = {n: 5}; o.n += 3; return o.n;", 8); // compound
checkRun("const o = {p: {v: 1}}; o.p.v = 99; return o.p.v;", 99); // nested target

// ── array element assignment ─────────────────────────────────────────────────────────────────────
checkRun("const a = [1, 2, 3]; a[1] = 20; return a[1];", 20);
checkRun("const a = [1, 2, 3]; a[0] = a[0] + a[2]; return a[0];", 4); // 1+3
checkRun("const a = [5]; a[1] = 10; return a[1];", 10); // i === length → append
checkRun("const a = [1, 2, 3]; a[2] += 7; return a[2];", 10); // compound

// ── computed keys + in-loop mutation ─────────────────────────────────────────────────────────────
checkRun("const o = {}; const k = \"key\"; o[k] = 42; return o[k];", 42); // computed string key
checkRun("const a = [0, 0, 0]; for (let i = 0; i < 3; i++) { a[i] = i * 10; } return a[0] + a[1] + a[2];", 30);
checkRun("const o = {}; o.count = 0; for (let i = 0; i < 5; i++) { o.count += 1; } return o.count;", 5);
checkRun("const m = [[1, 2], [3, 4]]; m[1][0] = 99; return m[1][0] + m[0][1];", 101); // 99 + 2

console.log("dynrt 2e.4 member assignment: all checks passed");
