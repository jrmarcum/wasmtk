// Driver for the wasmtk own dynamic runtime — #14 increment 2d.1: statements + control flow.
// `dynRun(src, env)` executes a sequence of JS statements (let/const/assignment, if/else, while,
// blocks, return) against a mutable environment object, returning the `return` value or the last
// expression value. Exercises real little programs — loops, conditionals, nested loops, early
// return, builtin calls inside statements — all over the shared heap.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves the statement interpreter.

type i32 = number;
type f64 = number;

import { dynRun, dynObject, dynStdEnv, dynTypeof, dynNumberValue } from "../dynrt_bundle/dynrt_lib_modc.wasm";

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

// run a program in a FRESH env with the built-ins; assert numeric result
function checkRunStd(src: string, expected: f64): void {
  const e: i32 = dynStdEnv();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── declarations + assignment ──────────────────────────────────────────────────────────────────
checkRun("let x = 5; x = x * 2; x = x + 1; return x;", 11);
checkRun("let a = 3; let b = 4; return a * a + b * b;", 25);
checkRun("let a = 3; a + 4;", 7); // no return → last expression value

// ── if / else ───────────────────────────────────────────────────────────────────────────────────
checkRun("let x = 7; let r = 0; if (x > 5) { r = 100; } else { r = 200; } return r;", 100);
checkRun("let x = 3; let r = 0; if (x > 5) { r = 100; } else { r = 200; } return r;", 200);
checkRun("let x = 10; if (x > 5) { return 1; } return 2;", 1); // early return
checkRun("let x = 1; if (x > 5) { return 1; } return 2;", 2);
checkRun("let x = 4; let r = -1; if (x > 5) { r = 1; } return r;", -1); // if with no else, false

// ── while loops ────────────────────────────────────────────────────────────────────────────────
checkRun("let sum = 0; let i = 0; while (i < 5) { sum = sum + i; i = i + 1; } return sum;", 10);
checkRun("let n = 5; let f = 1; while (n > 1) { f = f * n; n = n - 1; } return f;", 120); // 5!
checkRun("let a = 0; let b = 1; let n = 10; while (n > 0) { let t = a + b; a = b; b = t; n = n - 1; } return a;", 55); // fib(10)

// ── nested loops + conditionals ──────────────────────────────────────────────────────────────────
checkRun("let total = 0; let i = 0; while (i < 3) { let j = 0; while (j < 3) { total = total + 1; j = j + 1; } i = i + 1; } return total;", 9);
checkRun("let sum = 0; let i = 0; while (i < 10) { if (i > 4) { sum = sum + i; } i = i + 1; } return sum;", 35); // 5+6+7+8+9
checkRun("let x = 0; let i = 0; while (i < 6) { if (i > 3) { return x; } x = x + i; i = i + 1; } return x;", 6); // return out of a loop: 0+1+2+3

// ── builtin calls inside statements ──────────────────────────────────────────────────────────────
checkRunStd("let x = abs(-9); return sqrt(x);", 3);
checkRunStd("let m = max(3, 8); let n = min(m, 5); return n + 1;", 6);
checkRunStd("let s = 0; let i = 1; while (i <= 3) { s = s + abs(0 - i); i = i + 1; } return s;", 6); // 1+2+3

console.log("dynrt statements + control flow: all checks passed");
