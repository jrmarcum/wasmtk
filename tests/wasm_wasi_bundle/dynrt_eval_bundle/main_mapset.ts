// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.6: Map + Set in eval source.
// `new Map()` / `new Set(iterable)` build a dynrt object carrying internal key/value arrays. Map:
// set/get/has/delete/keys/values/forEach/size (chainable set). Set: add/has/delete/values/forEach/size
// (chainable add; constructor de-dups an array). Keys/values are arbitrary boxed values (numbers,
// strings, …) compared with === (linear scan). Methods dispatch in parsePostfix; `.size` via dynMember.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the Map + Set surface.

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

// ── Map: set / get / size / has ──────────────────────────────────────────────────────────────────
checkRun("const m = new Map(); m.set(\"a\", 10); m.set(\"b\", 20); return m.get(\"a\") + m.get(\"b\");", 30);
checkRun("const m = new Map(); m.set(\"x\", 1); m.set(\"y\", 2); return m.size;", 2);
checkRun("const m = new Map(); m.set(\"k\", 5); return m.has(\"k\") ? 100 : 200;", 100);
checkRun("const m = new Map(); m.set(\"k\", 5); return m.has(\"z\") ? 100 : 200;", 200);
checkRun("const m = new Map(); return m.get(\"nope\") === undefined ? 1 : 0;", 1);

// ── Map: update existing key (size unchanged) / numeric keys / chained set / delete ──────────────
checkRun("const m = new Map(); m.set(\"a\", 1); m.set(\"a\", 9); return m.get(\"a\") * 10 + m.size;", 91);
checkRun("const m = new Map(); m.set(1, 100); m.set(2, 200); return m.get(1) + m.get(2);", 300);
checkRun("const m = new Map(); m.set(\"a\", 1).set(\"b\", 2); return m.size;", 2);
checkRun("const m = new Map(); m.set(\"a\", 1); m.set(\"b\", 2); m.delete(\"a\"); return m.size * 10 + (m.has(\"a\") ? 1 : 0);", 10);

// ── Map: values / forEach ────────────────────────────────────────────────────────────────────────
checkRun("const m = new Map(); m.set(\"a\", 5); m.set(\"b\", 7); const v = m.values(); return v[0] + v[1];", 12);
checkRun("let sum = 0; const m = new Map(); m.set(\"a\", 3); m.set(\"b\", 4); m.forEach((v, k) => { sum = sum + v; }); return sum;", 7);

// ── Set: add / has / size / dedup ────────────────────────────────────────────────────────────────
checkRun("const s = new Set(); s.add(5); s.add(10); return s.has(5) ? 100 : 200;", 100);
checkRun("const s = new Set(); s.add(1); s.add(1); s.add(2); return s.size;", 2);
checkRun("const s = new Set(); s.add(1); s.add(2); s.add(3); return s.size;", 3);
checkRun("const s = new Set(); s.add(1); s.add(2); s.delete(1); return s.size * 10 + (s.has(1) ? 1 : 0);", 10);

// ── Set: init from array (de-dups) / values / forEach / chained add ──────────────────────────────
checkRun("const s = new Set([1, 2, 2, 3]); return s.size;", 3);
checkRun("const s = new Set(); s.add(10); s.add(20); const v = s.values(); return v[0] + v[1];", 30);
checkRun("let sum = 0; const s = new Set([4, 5, 6]); s.forEach((v) => { sum = sum + v; }); return sum;", 15);
checkRun("const s = new Set(); s.add(1).add(2).add(3); return s.size;", 3);

console.log("dynrt 2f.6 map + set: all checks passed");
