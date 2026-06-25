// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.3: function expressions +
// arrow functions in eval source. `function (p) { … }` and `(p) => …` / `p => …` / `() => …` build
// user function VALUES (closing over the current env), assignable, passable, returnable — enabling
// higher-order functions and closures inside dynamic code.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the function forms.

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

// ── function expressions ─────────────────────────────────────────────────────────────────────────
checkRun("const f = function(x) { return x * 2; }; return f(5);", 10);
checkRun("const add = function(a, b) { return a + b; }; return add(3, 4);", 7);
checkRun("const fac = function(n) { let p = 1; for (let i = 1; i <= n; i++) { p = p * i; } return p; }; return fac(5);", 120);

// ── arrow functions — block body, expression body, single param, no params ───────────────────────
checkRun("const f = (x) => { return x * 3; }; return f(4);", 12); // block body
checkRun("const f = (x) => x + 1; return f(41);", 42); // expression body
checkRun("const sq = x => x * x; return sq(6);", 36); // single param, no parens
checkRun("const add = (a, b) => a + b; return add(10, 20);", 30); // multi param
checkRun("const k = () => 99; return k();", 99); // no params

// ── higher-order + closures ──────────────────────────────────────────────────────────────────────
checkRun("const apply = function(f, x) { return f(x); }; const inc = y => y + 1; return apply(inc, 7);", 8);
checkRun("const make = function(n) { return x => x + n; }; const add5 = make(5); return add5(10);", 15); // closure over n
checkRun("const compose = (f, g) => x => f(g(x)); const inc = a => a + 1; const dbl = b => b * 2; const h = compose(inc, dbl); return h(5);", 11); // inc(dbl(5))

console.log("dynrt 2e.3 functions: all checks passed");
