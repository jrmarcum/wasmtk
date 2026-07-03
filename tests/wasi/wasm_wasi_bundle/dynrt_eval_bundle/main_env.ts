// Driver for the wasmtk own dynamic runtime — #14 increment 2b: variables + environment + member
// / index access. Builds an environment object (names → boxed values) with the value-model
// constructors, then evaluates expressions that reference those variables and navigate them via
// `.prop`, `["key"]`, and `[i]`. After the Phase 18 merge + Stage 0.6 allocator unification, the env
// and all results live on the driver's shared heap.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves env lookup + member access.

type i32 = number;
type f64 = number;

import { dynEvalEnv, dynObject, dynSet, dynNumber, dynString, dynArray, dynPush, dynTypeof, dynNumberValue, dynToBool, dynStrLen, dynStrCharAt } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

function checkNumEnv(src: string, env: i32, expected: f64): void {
  const v: i32 = dynEvalEnv(src, env);
  check(dynTypeof(v) === 3 ? 1 : 0);
  check(dynNumberValue(v) === expected ? 1 : 0);
}

// ── build an environment: { x:10, y:3, name:"wasmtk", pt:{a:1,b:2}, arr:[10,20,30] } ───────────
const env: i32 = dynObject();
dynSet(env, "x", dynNumber(10));
dynSet(env, "y", dynNumber(3));
dynSet(env, "name", dynString("wasmtk"));

const pt: i32 = dynObject();
dynSet(pt, "a", dynNumber(1));
dynSet(pt, "b", dynNumber(2));
dynSet(env, "pt", pt);

const arr: i32 = dynArray();
dynPush(arr, dynNumber(10));
dynPush(arr, dynNumber(20));
dynPush(arr, dynNumber(30));
dynSet(env, "arr", arr);

// ── variable references + arithmetic ───────────────────────────────────────────────────────────
checkNumEnv("x + 5", env, 15);
checkNumEnv("x * x", env, 100);
checkNumEnv("x - y", env, 7);
checkNumEnv("x / y + 1", env, 10 / 3 + 1);
checkNumEnv("(x + y) * 2", env, 26);

// ── object member access (.prop and ["key"]) ──────────────────────────────────────────────────
checkNumEnv("pt.a + pt.b", env, 3);
checkNumEnv("pt.a * 100 + pt.b", env, 102);
checkNumEnv("pt['a']", env, 1);
checkNumEnv("pt['b'] - pt['a']", env, 1);

// ── array index + .length ─────────────────────────────────────────────────────────────────────
checkNumEnv("arr[0] + arr[2]", env, 40);
checkNumEnv("arr[1] * 2", env, 40);
checkNumEnv("arr.length", env, 3);
checkNumEnv("arr[x - 9]", env, 20); // computed index: arr[1]

// ── string variable + .length ─────────────────────────────────────────────────────────────────
const nameVal: i32 = dynEvalEnv("name", env);
check(dynTypeof(nameVal) === 4 ? 1 : 0);
check(dynStrLen(nameVal) === 6 ? 1 : 0);
check(dynStrCharAt(nameVal, 0) === 119 ? 1 : 0); // 'w'
checkNumEnv("name.length", env, 6);

// ── absent variable / property → undefined; guarded member never traps ─────────────────────────
const miss: i32 = dynEvalEnv("missing", env);
check(dynTypeof(miss) === 0 ? 1 : 0); // undefined
const missProp: i32 = dynEvalEnv("pt.zzz", env);
check(dynTypeof(missProp) === 0 ? 1 : 0);
const guardMember: i32 = dynEvalEnv("undefined.x", env); // total/guarded → undefined, no trap
check(dynTypeof(guardMember) === 0 ? 1 : 0);

// ── variables in conditions / ternary ──────────────────────────────────────────────────────────
checkNumEnv("x > 5 ? pt.a : pt.b", env, 1);
checkNumEnv("y > 5 ? pt.a : pt.b", env, 2);
const sBig: i32 = dynEvalEnv("x > y ? 'big' : 'small'", env);
check(dynTypeof(sBig) === 4 ? 1 : 0);
check(dynStrLen(sBig) === 3 ? 1 : 0); // "big"

console.log("dynrt eval+env: all checks passed");
