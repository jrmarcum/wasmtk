// deno-fmt-ignore-file — checkRun(...) calls and the .wasm import MUST each stay on ONE line (wasic's
// statement + import detectors are line-based); deno fmt would otherwise wrap long lines and break it.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.9: generators (`function*` /
// `yield`) in eval source. The re-parse interpreter can't suspend a call stack, so generators use EAGER
// COLLECTION: calling a `function*` runs the body to completion, collecting each `yield` into an array;
// the returned generator object serves them via `.next()` → `{ value, done }` and via `for...of`. This
// covers FINITE generators (the common case); infinite generators are a documented v1 limitation.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves generators + next() + for-of.

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

// ── next(): value sequence + done ────────────────────────────────────────────────────────────────
checkRun("function* g() { yield 1; yield 2; yield 3; } const it = g(); return it.next().value;", 1);
checkRun("function* g() { yield 10; yield 20; } const it = g(); it.next(); return it.next().value;", 20);
checkRun("function* g() { yield 1; } const it = g(); it.next(); return it.next().done ? 100 : 200;", 100);
checkRun("function* g() { yield 1; } const it = g(); it.next(); return it.next().value === undefined ? 1 : 0;", 1);
checkRun("function* g() { } const it = g(); return it.next().done ? 1 : 0;", 1);

// ── for-of over a generator ──────────────────────────────────────────────────────────────────────
checkRun("function* g() { yield 1; yield 2; yield 3; } let sum = 0; for (const x of g()) { sum = sum + x; } return sum;", 6);
checkRun("function* g() { yield 1; yield 2; yield 3; yield 4; } let n = 0; for (const x of g()) { n = n + 1; } return n;", 4);

// ── generators with loops / params / computed yields ─────────────────────────────────────────────
checkRun("function* range(n) { let i = 0; while (i < n) { yield i; i = i + 1; } } let sum = 0; for (const x of range(4)) { sum = sum + x; } return sum;", 6);
checkRun("function* squares(n) { let i = 1; while (i <= n) { yield i * i; i = i + 1; } } let sum = 0; for (const x of squares(3)) { sum = sum + x; } return sum;", 14);
checkRun("function* g(a, b) { yield a; yield b; yield a + b; } let sum = 0; for (const x of g(3, 4)) { sum = sum + x; } return sum;", 14);

// ── conditional yield ────────────────────────────────────────────────────────────────────────────
checkRun("function* g(n) { let i = 0; while (i < n) { if (i % 2 === 0) { yield i; } i = i + 1; } } let sum = 0; for (const x of g(6)) { sum = sum + x; } return sum;", 6);

// ── nested generators (each collects into its own array; rooted across nested calls) ─────────────
checkRun("function* a() { yield 1; yield 2; } function* b() { yield 10; yield 20; } let sum = 0; for (const x of a()) { for (const y of b()) { sum = sum + x * y; } } return sum;", 90);

console.log("dynrt 2e.9 generators: all checks passed");
