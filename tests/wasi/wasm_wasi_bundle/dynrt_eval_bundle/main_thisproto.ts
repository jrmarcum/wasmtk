// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2f.1: `this` + prototype (the
// object-model foundation that 2e.8 classes build on). Object-literal method shorthand `{ m() {…} }`
// (and `m: function(){…}`) creates a function-valued property; calling `obj.m(args)` binds `this` to the
// receiver, so `this.field` reads/writes the receiver. `Object.create(proto)` makes an object whose
// __proto__ is `proto`; member lookup walks the prototype chain (own props shadow inherited ones).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves `this`/method-dispatch/prototype.

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

// ── method shorthand + `this` read ───────────────────────────────────────────────────────────────
checkRun("const o = { v: 5, get() { return this.v; } }; return o.get();", 5);
checkRun("const o = { base: 10, add(x) { return this.base + x; } }; return o.add(5);", 15);

// ── `m: function(){}` form binds `this` too ──────────────────────────────────────────────────────
checkRun("const o = { v: 7, f: function () { return this.v * 2; } }; return o.f();", 14);

// ── `this.field = …` write through the receiver ──────────────────────────────────────────────────
checkRun("const o = { c: 0, inc() { this.c = this.c + 1; } }; o.inc(); o.inc(); o.inc(); return o.c;", 3);

// ── method calling another method via `this.other()` ─────────────────────────────────────────────
checkRun("const o = { x: 3, dbl() { return this.x * 2; }, quad() { return this.dbl() * 2; } }; return o.quad();", 12);

// ── a plain (non-method) call has `this === undefined` ───────────────────────────────────────────
checkRun("function f() { return this === undefined ? 100 : 200; } return f();", 100);

// ── prototype: method inherited from proto, `this` is the receiver, fields live on the receiver ───
checkRun("const proto = { area() { return this.w * this.h; } }; const r = Object.create(proto); r.w = 4; r.h = 5; return r.area();", 20);

// ── prototype chain: inherited field, then own property shadows it ───────────────────────────────
checkRun("const proto = { tag: 99 }; const o = Object.create(proto); return o.tag;", 99);
checkRun("const proto = { tag: 99 }; const o = Object.create(proto); o.tag = 7; return o.tag;", 7);

console.log("dynrt 2f.1 this + prototype: all checks passed");
