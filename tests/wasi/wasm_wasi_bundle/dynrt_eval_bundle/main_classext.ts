// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.8a: COMPLETE the class feature.
// `extends` (prototype-chained inheritance) + `super(args)` (base constructor) + `super.method(args)`
// (base method, this=instance); `static` methods + fields (on the class object); instance fields
// (`x = expr;` → constructor preamble); and getters/setters (`get x(){…}` / `set x(v){…}` → called on
// member read/write). Builds on the 2e.8 core (class/constructor/new) + the 2f.1 this+prototype model.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves inheritance + accessors + statics.

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

// ── extends + inherited method ───────────────────────────────────────────────────────────────────
checkRun("class A { val() { return 7; } } class B extends A {} const b = new B(); return b.val();", 7);

// ── extends + super(...) base constructor ────────────────────────────────────────────────────────
checkRun("class Animal { constructor(n) { this.legs = 4; } getLegs() { return this.legs; } } class Dog extends Animal { constructor() { super(\"dog\"); this.tail = 1; } } const d = new Dog(); return d.getLegs() + d.tail;", 5);

// ── super.method() calls the overridden base method ──────────────────────────────────────────────
checkRun("class Base { greet() { return 10; } } class Sub extends Base { greet() { return super.greet() + 5; } } const o = new Sub(); return o.greet();", 15);

// ── three-level super() chain ────────────────────────────────────────────────────────────────────
checkRun("class A { constructor() { this.a = 1; } } class B extends A { constructor() { super(); this.b = 2; } } class C extends B { constructor() { super(); this.c = 3; } } const o = new C(); return o.a + o.b * 10 + o.c * 100;", 321);

// ── static method + static field ─────────────────────────────────────────────────────────────────
checkRun("class MathUtil { static square(x) { return x * x; } } return MathUtil.square(6);", 36);
checkRun("class Config { static version = 42; } return Config.version;", 42);

// ── instance fields (constructor preamble) ───────────────────────────────────────────────────────
checkRun("class Point { x = 1; y = 2; getSum() { return this.x + this.y; } } const p = new Point(); return p.getSum();", 3);
checkRun("class Acc { count = 0; constructor(start) { this.count = start; } bump() { this.count = this.count + 1; return this.count; } } const a = new Acc(10); a.bump(); return a.bump();", 12);

// ── getter ───────────────────────────────────────────────────────────────────────────────────────
checkRun("class Circle { constructor(r) { this.r = r; } get area() { return this.r * this.r * 3; } } const c = new Circle(2); return c.area;", 12);

// ── setter + getter round-trip ───────────────────────────────────────────────────────────────────
checkRun("class Temp { constructor() { this.c = 0; } set celsius(v) { this.c = v; } get celsius() { return this.c; } } const t = new Temp(); t.celsius = 25; return t.celsius;", 25);

console.log("dynrt 2e.8a class completion: all checks passed");
