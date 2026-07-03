// Driver for the wasmtk own dynamic runtime — #14 increment 2d.2: user-defined functions +
// `new Function`. Exercises (a) in-source `function name(params){body}` declarations with recursion
// and closures over the defining scope, and (b) `dynMakeFunc(paramsArr, bodyStr, env)` — the
// `new Function` capability (build a callable from STRINGS at runtime) — then calls them through
// `dynEvalEnv`. All over the shared heap.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves user functions.

type i32 = number;
type f64 = number;

import { dynRun, dynEvalEnv, dynObject, dynStdEnv, dynMakeFunc, dynArray, dynPush, dynString, dynSet, dynTypeof, dynNumberValue } from "../dynrt_bundle/dynrt_lib_modc.wasm";

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

function checkRunStd(src: string, expected: f64): void {
  const e: i32 = dynStdEnv();
  const r: i32 = dynRun(src, e);
  check(dynTypeof(r) === 3 ? 1 : 0);
  check(dynNumberValue(r) === expected ? 1 : 0);
}

// ── in-source function declarations + calls ──────────────────────────────────────────────────────
checkRun("function add(a, b) { return a + b; } return add(2, 3);", 5);
checkRun("function sq(x) { return x * x; } return sq(7);", 49);
checkRun("function f(a, b) { return a - b; } return f(10, 3);", 7);
checkRun("function g(a, b) { return a; } return g(42);", 42); // missing arg → undefined, unused

// ── recursion (needs the scope chain: the body resolves its own name in the defining env) ────────
checkRun("function fact(n) { if (n < 2) { return 1; } return n * fact(n - 1); } return fact(5);", 120);
// fib(8) — depth kept modest: each call re-parses the body via a nested dynRun, so interpreter
// recursion is bound by V8's WASM call-stack (separate from the heap limit GC Part 1 lifted). The
// deep-recursion HEAP test is 18r's fib(15).
checkRun("function fib(n) { if (n < 2) { return n; } return fib(n - 1) + fib(n - 2); } return fib(8);", 21);

// ── closure over the defining scope (outer variable visible in the body) ─────────────────────────
checkRun("let base = 100; function addBase(x) { return x + base; } return addBase(5);", 105);

// ── multiple functions calling each other ────────────────────────────────────────────────────────
checkRun("function sq(x){return x*x;} function sumsq(a,b){return sq(a)+sq(b);} return sumsq(3,4);", 25);

// ── a function that itself uses statements (locals + a loop) ─────────────────────────────────────
checkRun("function sumTo(n){let s=0;let i=1;while(i<=n){s=s+i;i=i+1;}return s;} return sumTo(5);", 15);

// ── functions calling built-ins ──────────────────────────────────────────────────────────────────
checkRunStd("function hyp(a, b) { return sqrt(a * a + b * b); } return hyp(3, 4);", 5);

// ── `new Function`: build a callable from STRINGS at runtime, then call it via eval ──────────────
const env: i32 = dynStdEnv();

// f = new Function("a", "b", "return a + b;")
const p2: i32 = dynArray();
dynPush(p2, dynString("a"));
dynPush(p2, dynString("b"));
const fAdd: i32 = dynMakeFunc(p2, "return a + b;", env);
dynSet(env, "f", fAdd);
const r1: i32 = dynEvalEnv("f(5, 7)", env);
check(dynTypeof(r1) === 3 ? 1 : 0);
check(dynNumberValue(r1) === 12 ? 1 : 0);

// sumTo = new Function("n", "let s=0;let i=0;while(i<n){s=s+i;i=i+1;}return s;")
const p1: i32 = dynArray();
dynPush(p1, dynString("n"));
const fSum: i32 = dynMakeFunc(p1, "let s=0;let i=0;while(i<n){s=s+i;i=i+1;}return s;", env);
dynSet(env, "sumTo", fSum);
const r2: i32 = dynEvalEnv("sumTo(5)", env);
check(dynNumberValue(r2) === 10 ? 1 : 0); // 0+1+2+3+4
const r3: i32 = dynEvalEnv("sumTo(5) + f(1, 1)", env); // 10 + 2
check(dynNumberValue(r3) === 12 ? 1 : 0);

console.log("dynrt user functions + new Function: all checks passed");
