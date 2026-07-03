// deno-fmt-ignore-file — the .wasm-import below MUST stay on one line (the import detector is
// line-based); deno fmt would otherwise wrap it and break compilation.
//
// Driver for the wasmtk own dynamic runtime — #14 Route A increment 2e.1: control flow.
// Extends the 2d.1 statement interpreter (`dynRun`) with C-style `for`, `for…of`, `do…while`,
// `break`/`continue`, and the `++`/`--`/`+=`/`-=`/`*=`/`/=` update forms (so for-loops are idiomatic).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of bounds,
// trapping the module (nonzero exit), so a successful `run` proves the control-flow interpreter.

type i32 = number;
type f64 = number;

// NOTE: the .wasm-import detector only matches a SINGLE-LINE import — keep this on one line.
// deno-fmt-ignore
import { dynArray, dynNumber, dynNumberValue, dynObject, dynPush, dynRun, dynSet, dynTypeof } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// run a program in a FRESH plain env; assert numeric result
function checkRun(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── C-style for ──────────────────────────────────────────────────────────────────────────────────
checkRun("let s = 0; for (let i = 0; i < 5; i = i + 1) { s = s + i; } return s;", 10); // 0+1+2+3+4
checkRun("let s = 0; for (let i = 0; i < 5; i++) { s = s + i; } return s;", 10); // ++ update
checkRun("let p = 1; for (let i = 1; i <= 5; i++) { p = p * i; } return p;", 120); // 5!
checkRun("let s = 0; for (let i = 0; i < 10; i += 2) { s = s + i; } return s;", 20); // 0+2+4+6+8
checkRun("let s = 0; for (let i = 10; i > 0; i--) { s = s + i; } return s;", 55); // 10..1
checkRun("let s = 0; let i = 0; for (; i < 4; i++) { s = s + i; } return s;", 6); // empty init

// ── break / continue ─────────────────────────────────────────────────────────────────────────────
checkRun("let s = 0; for (let i = 0; i < 100; i++) { if (i >= 5) { break; } s = s + i; } return s;", 10);
checkRun("let s = 0; for (let i = 0; i < 10; i++) { if (i > 4) { continue; } s = s + i; } return s;", 10);
checkRun("let s = 0; let i = 0; while (i < 100) { i++; if (i > 5) { break; } s = s + i; } return s;", 15);
checkRun("let s = 0; let i = 0; while (i < 6) { i++; if (i === 3) { continue; } s = s + i; } return s;", 18); // 1+2+4+5+6

// ── do…while ─────────────────────────────────────────────────────────────────────────────────────
checkRun("let n = 0; let s = 0; do { s = s + n; n++; } while (n < 5); return s;", 10); // 0+1+2+3+4
checkRun("let x = 0; do { x++; } while (x < 1); return x;", 1); // body runs at least once

// ── nested loops ─────────────────────────────────────────────────────────────────────────────────
checkRun("let t = 0; for (let i = 0; i < 3; i++) { for (let j = 0; j < 3; j++) { t = t + 1; } } return t;", 9);
checkRun("let t = 0; for (let i = 0; i < 3; i++) { for (let j = 0; j < 5; j++) { if (j >= 2) { break; } t = t + 1; } } return t;", 6);

// ── for…of over an array bound in the env (array literals in eval source arrive in 2e.2) ───────────
function checkForOf(src: string, expected: f64): void {
  const e: i32 = dynObject();
  const arr: i32 = dynArray();
  dynPush(arr, dynNumber(10));
  dynPush(arr, dynNumber(20));
  dynPush(arr, dynNumber(30));
  dynSet(e, "items", arr);
  const r: i32 = dynRun(src, e);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

checkForOf("let s = 0; for (const x of items) { s = s + x; } return s;", 60);
checkForOf("let s = 0; for (const x of items) { if (x === 20) { continue; } s = s + x; } return s;", 40);
checkForOf("let s = 0; for (const x of items) { if (x === 20) { break; } s = s + x; } return s;", 10);

// ── for…in over an object's keys ─────────────────────────────────────────────────────────────────
checkRun("const o = {a: 1, b: 2, c: 3}; let n = 0; for (const k in o) { n++; } return n;", 3); // key count
checkRun("const o = {a: 1, b: 2, c: 3}; let s = 0; for (const k in o) { s = s + o[k]; } return s;", 6); // sum via o[k]
checkRun("const o = {a: 5, b: 10}; let s = 0; for (const k in o) { if (o[k] === 5) { continue; } s = s + o[k]; } return s;", 10);

// ── switch (fall-through, break, default, literal disc) ──────────────────────────────────────────
checkRun("let r = 0; const x = 2; switch (x) { case 1: r = 10; break; case 2: r = 20; break; case 3: r = 30; break; } return r;", 20);
checkRun("let r = 0; const x = 9; switch (x) { case 1: r = 10; break; default: r = 99; } return r;", 99); // default
checkRun("let r = 0; const x = 1; switch (x) { case 1: case 2: r = 5; break; case 3: r = 30; } return r;", 5); // empty-case fall-through
checkRun("let r = 0; const x = 1; switch (x) { case 1: r = r + 1; case 2: r = r + 10; break; case 3: r = r + 100; } return r;", 11); // body fall-through
checkRun("let r = 0; switch (3) { case 1: r = 1; break; case 3: r = 3; break; } return r;", 3); // literal discriminant

console.log("dynrt 2e.1 control flow: all checks passed");
