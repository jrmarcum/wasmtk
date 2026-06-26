// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.8: CLASSES (built on the 2f.1
// `this`+prototype foundation). `class Name { constructor(p){…} method(p){…} }` builds a class value
// (prototype object holding the methods + the constructor); `new Name(args)` makes an instance whose
// __proto__ is the prototype, runs the constructor with `this`=instance (so `this.field = …` populates
// it), and method calls dispatch through the prototype chain binding `this` to the receiver. Instances
// are independent. No extends/super/static/fields in v1.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves class construction + method dispatch.

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

// ── constructor + method ─────────────────────────────────────────────────────────────────────────
checkRun("class Point { constructor(x) { this.x = x; } getX() { return this.x; } } const p = new Point(5); return p.getX();", 5);
checkRun("class Rect { constructor(w, h) { this.w = w; this.h = h; } area() { return this.w * this.h; } } const r = new Rect(4, 6); return r.area();", 24);

// ── method with args ─────────────────────────────────────────────────────────────────────────────
checkRun("class Adder { constructor(base) { this.base = base; } add(x) { return this.base + x; } } const a = new Adder(100); return a.add(23);", 123);

// ── constructor computing a field ────────────────────────────────────────────────────────────────
checkRun("class Sum { constructor(a, b) { this.total = a + b; } } const s = new Sum(7, 8); return s.total;", 15);

// ── mutating method across calls ─────────────────────────────────────────────────────────────────
checkRun("class Counter { constructor() { this.n = 0; } inc() { this.n = this.n + 1; } get() { return this.n; } } const c = new Counter(); c.inc(); c.inc(); c.inc(); return c.get();", 3);

// ── method calling a sibling method via this ─────────────────────────────────────────────────────
checkRun("class Calc { constructor(v) { this.v = v; } dbl() { return this.v * 2; } quad() { return this.dbl() * 2; } } const c = new Calc(3); return c.quad();", 12);

// ── independent instances ────────────────────────────────────────────────────────────────────────
checkRun("class Box { constructor(v) { this.v = v; } get() { return this.v; } } const a = new Box(10); const b = new Box(20); return a.get() + b.get() * 100;", 2010);

// ── no constructor ───────────────────────────────────────────────────────────────────────────────
checkRun("class Konst { val() { return 42; } } const k = new Konst(); return k.val();", 42);

// ── method returns a this-derived running value ──────────────────────────────────────────────────
checkRun("class Acc { constructor() { this.sum = 0; } add(x) { this.sum = this.sum + x; return this.sum; } } const a = new Acc(); a.add(5); a.add(10); return a.add(3);", 18);

console.log("dynrt 2e.8 classes: all checks passed");
