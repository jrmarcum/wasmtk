// Virtual-import driver for the wasmtk own dynamic runtime (#14, increment 1b).
//
// Instead of importing the runtime from a fixture `.wasm` path (the 18j pipeline), this driver
// imports it BY NAME via the `wasmtk:dynrt` specifier. The dynamic-runtime library is embedded in
// the compiler (src/wasm/caps_bytes.ts) and merged on demand — so the pipeline is just compile +
// run (no separate `modc` step), and only the capability actually imported gets bundled
// (feature-level tree-shake, stdlib-bundling brief §7-#4).
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves the dynamic runtime
// works over the shared heap when pulled in through the virtual-import path.

type i32 = number;
type f64 = number;

import { dynUndefined, dynNull, dynBool, dynNumber, dynString, dynArray, dynObject, dynTypeof, dynNumberValue, dynToBool, dynSet, dynGet, dynHas, dynObjLen, dynPush, dynArrLen, dynArrGet, dynStrictEq, dynAdd, dynStrLen, dynStrCharAt } from "wasmtk:dynrt";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// Primitives + typeof (incl. the null → "object" quirk).
check(dynTypeof(dynUndefined()) === 0 ? 1 : 0);
check(dynTypeof(dynNull()) === 1 ? 1 : 0);
check(dynTypeof(dynBool(1)) === 2 ? 1 : 0);
check(dynToBool(dynBool(0)) === 0 ? 1 : 0);

// Number (real f64).
const num: i32 = dynNumber(6.25);
check(dynTypeof(num) === 3 ? 1 : 0);
check(dynNumberValue(num) === 6.25 ? 1 : 0);

// Object: set / get / has / overwrite.
const obj: i32 = dynObject();
dynSet(obj, "a", dynNumber(1));
dynSet(obj, "b", dynString("two"));
check(dynObjLen(obj) === 2 ? 1 : 0);
check(dynHas(obj, "a") === 1 ? 1 : 0);
check(dynHas(obj, "z") === 0 ? 1 : 0);
check(dynNumberValue(dynGet(obj, "a")) === 1 ? 1 : 0);
dynSet(obj, "a", dynNumber(42));
check(dynObjLen(obj) === 2 ? 1 : 0);
check(dynNumberValue(dynGet(obj, "a")) === 42 ? 1 : 0);

// Array: push past initial capacity (forces growth → node pointer write-back).
const arr: i32 = dynArray();
let i: i32 = 0;
while (i < 8) {
  dynPush(arr, dynNumber(i + 1));
  i = i + 1;
}
console.log("arr len:", dynArrLen(arr));
check(dynArrLen(arr) === 8 ? 1 : 0);
check(dynNumberValue(dynArrGet(arr, 0)) === 1 ? 1 : 0);
check(dynNumberValue(dynArrGet(arr, 7)) === 8 ? 1 : 0);

// Operators: === and +.
check(dynStrictEq(dynNumber(5), dynNumber(5)) === 1 ? 1 : 0);
check(dynStrictEq(dynString("ab"), dynString("ab")) === 1 ? 1 : 0);
check(dynStrictEq(dynNull(), dynUndefined()) === 0 ? 1 : 0);
const sum: i32 = dynAdd(dynNumber(10), dynNumber(20));
console.log("10 + 20 =", dynNumberValue(sum));
check(dynNumberValue(sum) === 30 ? 1 : 0);
const cat: i32 = dynAdd(dynString("ab"), dynString("cd"));
check(dynStrLen(cat) === 4 ? 1 : 0);
check(dynStrCharAt(cat, 2) === 99 ? 1 : 0); // 'c'

console.log("dynrt virtual-import: all checks passed");
