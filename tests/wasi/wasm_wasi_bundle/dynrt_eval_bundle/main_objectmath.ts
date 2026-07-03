// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.4: Object + Math statics in eval
// source. Math.floor/ceil/round/abs/sqrt/sign/trunc/min/max/pow + Math.PI/Math.E; Object.keys/values/
// entries/assign (Object.create was 2f.1). Both are special-cased in parsePrimary as namespace statics
// (`Math.foo(args)` / `Object.foo(args)`); Math reuses the wasic compiler's f64 intrinsics.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the Object + Math surface.

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

// ── Math: rounding family ────────────────────────────────────────────────────────────────────────
checkRun("return Math.floor(3.7);", 3);
checkRun("return Math.ceil(3.2);", 4);
checkRun("return Math.round(2.5);", 3);
checkRun("return Math.trunc(4.9);", 4);
checkRun("return Math.trunc(-4.9);", -4);

// ── Math: abs / sqrt / sign / min / max / pow ────────────────────────────────────────────────────
checkRun("return Math.abs(-5);", 5);
checkRun("return Math.sqrt(16);", 4);
checkRun("return Math.sign(-3);", -1);
checkRun("return Math.sign(7);", 1);
checkRun("return Math.sign(0);", 0);
checkRun("return Math.min(3, 7);", 3);
checkRun("return Math.max(3, 7);", 7);
checkRun("return Math.pow(2, 10);", 1024);

// ── Math: constants ──────────────────────────────────────────────────────────────────────────────
checkRun("return Math.floor(Math.PI * 100);", 314);
checkRun("return Math.floor(Math.E * 100);", 271);

// ── Math: nested / composed ──────────────────────────────────────────────────────────────────────
checkRun("return Math.max(Math.abs(-8), Math.sqrt(49));", 8);

// ── Object: keys / values / entries / assign ─────────────────────────────────────────────────────
checkRun("const o = { a: 1, b: 2, c: 3 }; return Object.keys(o).length;", 3);
checkRun("const o = { a: 10, b: 20 }; const v = Object.values(o); return v[0] + v[1];", 30);
checkRun("const o = { x: 5 }; const e = Object.entries(o); return e[0][1];", 5);
checkRun("const o = { name: 1 }; return Object.keys(o)[0].charCodeAt(0);", 110);
checkRun("const o = { x: 5 }; const e = Object.entries(o); return e[0][0].charCodeAt(0);", 120);
checkRun("const t = { a: 1 }; Object.assign(t, { b: 2 }, { c: 3 }); return t.a + t.b + t.c;", 6);
checkRun("const t = { a: 1 }; Object.assign(t, { a: 9 }); return t.a;", 9);

console.log("dynrt 2f.4 object + math: all checks passed");
