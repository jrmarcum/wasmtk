// Driver for the wasmtk own dynamic runtime — #14 increment 2c: function values + calls + REAL
// short-circuit. Uses `dynStdEnv()` (built-ins abs/sqrt/floor/ceil/round/min/max/len + the
// side-effecting `inc`) as the environment, evaluates call expressions, and proves short-circuit by
// observing the `inc()` side-effect counter (a dead `inc()` must NOT run).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves calls + short-circuit.

type i32 = number;
type f64 = number;

import { dynEvalEnv, dynStdEnv, dynSet, dynNumber, dynString, dynArray, dynPush, dynTypeof, dynNumberValue, dynStrLen, dynSideEffectCount, dynResetSideEffects } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// ── environment: built-ins + a couple of variables ─────────────────────────────────────────────
const env: i32 = dynStdEnv();
dynSet(env, "x", dynNumber(10));
const arr: i32 = dynArray();
dynPush(arr, dynNumber(1));
dynPush(arr, dynNumber(2));
dynPush(arr, dynNumber(3));
dynPush(arr, dynNumber(4));
dynSet(env, "arr", arr);

function checkNumEnv(src: string, e: i32, expected: f64): void {
  const v: i32 = dynEvalEnv(src, e);
  check(dynTypeof(v) === 3 ? 1 : 0);
  check(dynNumberValue(v) === expected ? 1 : 0);
}

// reset, evaluate, assert the side-effect counter (how many live inc() calls happened)
function checkSC(src: string, e: i32, expectedCount: i32): void {
  dynResetSideEffects();
  const v: i32 = dynEvalEnv(src, e);
  check(dynSideEffectCount() === expectedCount ? 1 : 0);
}

// ── built-in calls ──────────────────────────────────────────────────────────────────────────────
checkNumEnv("abs(-5)", env, 5);
checkNumEnv("sqrt(16)", env, 4);
checkNumEnv("floor(3.7)", env, 3);
checkNumEnv("ceil(3.2)", env, 4);
checkNumEnv("round(2.5)", env, 3);
checkNumEnv("min(3, 7)", env, 3);
checkNumEnv("max(3, 7)", env, 7);
checkNumEnv("len('hello')", env, 5);
checkNumEnv("len(arr)", env, 4);

// ── calls over variables + nesting + composition ──────────────────────────────────────────────
checkNumEnv("abs(x - 15)", env, 5);          // abs(10 - 15)
checkNumEnv("max(x, 7) + 1", env, 11);
checkNumEnv("sqrt(x + 6)", env, 4);          // sqrt(16)
checkNumEnv("abs(-3) + sqrt(9)", env, 6);
checkNumEnv("max(abs(-5), 2)", env, 5);      // nested call as arg
checkNumEnv("min(max(1, 8), 5)", env, 5);

// ── function value typeof ──────────────────────────────────────────────────────────────────────
const fv: i32 = dynEvalEnv("abs", env);
check(dynTypeof(fv) === 5 ? 1 : 0); // function

// ── REAL short-circuit (observed via the inc() side-effect counter) ───────────────────────────
checkSC("false && inc()", env, 0);  // && skips right when left is falsy
checkSC("true && inc()", env, 1);
checkSC("true || inc()", env, 0);   // || skips right when left is truthy
checkSC("false || inc()", env, 1);
checkSC("false ? inc() : 5", env, 0);     // ternary: dead branch not run
checkSC("true ? inc() : inc()", env, 1);  // only the taken branch runs
checkSC("true && true && inc()", env, 1); // chained &&
checkSC("false && inc() && inc()", env, 0); // both right calls dead
checkSC("max(false && inc(), true && inc())", env, 1); // short-circuit inside call args
checkSC("inc() + inc()", env, 2);         // both live → counter 2

// inc() returns the running count (1 then 2) → 1 + 2 = 3
dynResetSideEffects();
const sumInc: i32 = dynEvalEnv("inc() + inc()", env);
check(dynNumberValue(sumInc) === 3 ? 1 : 0);

console.log("dynrt eval calls + short-circuit: all checks passed");
