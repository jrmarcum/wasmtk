// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.5: JSON in eval source.
// `JSON.parse(str)` reuses the interpreter's own literal parser (JSON ⊂ the expression grammar) to build
// native dynrt objects/arrays/strings/numbers/bool/null; `JSON.stringify(value)` recursively serializes a
// dynrt value. The JSON documents are wrapped in SINGLE-quoted eval-source strings so the inner
// double-quoted JSON needs no extra escaping. parse∘stringify round-trips are the strongest checks.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves JSON parse + stringify.

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

// ── JSON.parse — object / array / nested / scalars ───────────────────────────────────────────────
checkRun("const o = JSON.parse('{\"a\": 1, \"b\": 2}'); return o.a + o.b;", 3);
checkRun("const a = JSON.parse('[10, 20, 30]'); return a[0] + a[1] + a[2];", 60);
checkRun("const o = JSON.parse('{\"items\": [1, 2, 3]}'); return o.items.length;", 3);
checkRun("const o = JSON.parse('{\"p\": {\"x\": 5, \"y\": 7}}'); return o.p.x + o.p.y;", 12);
checkRun("return JSON.parse('42');", 42);
checkRun("return JSON.parse('true') ? 100 : 200;", 100);
checkRun("const s = JSON.parse('\"hello\"'); return s.length;", 5);
checkRun("const a = JSON.parse('[{\"v\": 1}, {\"v\": 2}]'); return a[0].v + a[1].v;", 3);

// ── JSON.stringify — length spot-checks ──────────────────────────────────────────────────────────
checkRun("const s = JSON.stringify({ a: 1 }); return s.length;", 7); // {"a":1}
checkRun("const s = JSON.stringify([1, 2, 3]); return s.length;", 7); // [1,2,3]
checkRun("const s = JSON.stringify(42); return s.length;", 2); // 42
checkRun("const s = JSON.stringify(\"hi\"); return s.length;", 4); // "hi"
checkRun("const s = JSON.stringify(true); return s.length;", 4); // true

// ── parse ∘ stringify round-trips (the strongest checks) ─────────────────────────────────────────
checkRun("const o = JSON.parse(JSON.stringify({ a: 5, b: 10 })); return o.a + o.b;", 15);
checkRun("const a = JSON.parse(JSON.stringify([7, 8, 9])); return a[0] + a[2];", 16);
checkRun("const o = JSON.parse(JSON.stringify({ p: { x: 3, y: 4 } })); return o.p.x + o.p.y;", 7);
checkRun("const o = JSON.parse(JSON.stringify({ list: [1, 2, 3, 4] })); return o.list.length;", 4);

console.log("dynrt 2f.5 JSON: all checks passed");
