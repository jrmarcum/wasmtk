// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.11: the remaining ES6 surface
// in eval source — `instanceof`, object spread `{ ...o }`, call spread `f(...args)`, array/object
// destructuring (`const [a, b] = …`, `const { x, y } = …`), and class expressions (`const C = class {…}`).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the whole 2e.11 surface.

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

// ── instanceof (walks the instance __proto__ chain for the class prototype) ────────────────────────
checkRun("class A {} class B extends A {} const b = new B(); return (b instanceof B) ? 1 : 0;", 1);
checkRun("class A {} class B extends A {} const b = new B(); return (b instanceof A) ? 1 : 0;", 1);
checkRun("class A {} class C {} const a = new A(); return (a instanceof C) ? 1 : 0;", 0);
checkRun("class A {} const a = new A(); return ({} instanceof A) ? 1 : 0;", 0);

// ── object spread { ...src } (later keys win) ──────────────────────────────────────────────────────
checkRun("const a = { x: 1, y: 2 }; const b = { ...a, z: 3 }; return b.x + b.y + b.z;", 6);
checkRun("const a = { x: 5 }; const b = { ...a, x: 8 }; return b.x;", 8);
checkRun("const a = { x: 1 }; const b = { x: 9, ...a }; return b.x;", 1);

// ── call spread f(...args) ─────────────────────────────────────────────────────────────────────────
checkRun("function add(a, b, c) { return a + b + c; } const xs = [1, 2, 3]; return add(...xs);", 6);
checkRun("function add(a, b, c) { return a + b + c; } return add(1, ...[2, 3]);", 6);

// ── array destructuring (incl. holes and missing → undefined) ──────────────────────────────────────
checkRun("const [a, b] = [10, 20]; return a + b;", 30);
checkRun("const [a, , c] = [1, 2, 3]; return a + c;", 4);
checkRun("const [a, b, c] = [7]; return (b === undefined) ? a : 0;", 7);

// ── object destructuring (incl. rename `key: alias`) ───────────────────────────────────────────────
checkRun("const { x, y } = { x: 4, y: 5 }; return x + y;", 9);
checkRun("const { a: p, b: q } = { a: 11, b: 22 }; return p + q;", 33);
checkRun("const o = { m: 100 }; const { m, n } = o; return (n === undefined) ? m : 0;", 100);

// ── class expressions (anonymous + extends) ────────────────────────────────────────────────────────
checkRun("const C = class { constructor(v) { this.v = v; } get() { return this.v; } }; const c = new C(7); return c.get();", 7);
checkRun("const Base = class { id() { return 5; } }; const Sub = class extends Base {}; const s = new Sub(); return s.id();", 5);

console.log("dynrt 2e.11 ES6 misc: all checks passed");
