// Shared-heap driver for the wasmtk own dynamic runtime — #14 increment 1 (value + object model).
//
// Imports the modc-compiled dynamic-runtime library. After the Phase 18 merge + Stage 0.6
// allocator unification, every $__malloc inside the library resolves to THIS module's bump cursor,
// so the boxed values the runtime builds live on the same heap this program uses.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module so the `run` step exits non-zero and the test fails. (A wasic
// uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)

type i32 = number;
type f64 = number;

import { dynUndefined, dynNull, dynBool, dynNumber, dynString, dynArray, dynObject, dynTag, dynTypeof, dynNumberValue, dynBoolValue, dynStrLen, dynStrCharAt, dynToBool, dynToNumber, dynSet, dynGet, dynHas, dynObjLen, dynPush, dynArrLen, dynArrGet, dynStrictEq, dynAdd } from "./dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// ── undefined / null: typeof quirk (null → "object") + distinct tags ──────────────────────────
const u: i32 = dynUndefined();
const nul: i32 = dynNull();
console.log("typeof undefined:", dynTypeof(u));
check(dynTypeof(u) === 0 ? 1 : 0);
console.log("typeof null:", dynTypeof(nul));
check(dynTypeof(nul) === 1 ? 1 : 0); // null is "object" in JS
check(dynTag(u) === 0 ? 1 : 0);
check(dynTag(nul) === 1 ? 1 : 0);
check(dynToBool(u) === 0 ? 1 : 0);
check(dynToBool(nul) === 0 ? 1 : 0);
check(dynToNumber(nul) === 0 ? 1 : 0);

// ── boolean ───────────────────────────────────────────────────────────────────────────────────
const bt: i32 = dynBool(1);
const bf: i32 = dynBool(0);
console.log("typeof true:", dynTypeof(bt));
check(dynTypeof(bt) === 2 ? 1 : 0);
check(dynBoolValue(bt) === 1 ? 1 : 0);
check(dynToBool(bt) === 1 ? 1 : 0);
check(dynToBool(bf) === 0 ? 1 : 0);
check(dynToNumber(bt) === 1 ? 1 : 0);

// ── number (real f64) ──────────────────────────────────────────────────────────────────────────
const num: i32 = dynNumber(42.5);
console.log("typeof number:", dynTypeof(num));
check(dynTypeof(num) === 3 ? 1 : 0);
check(dynNumberValue(num) === 42.5 ? 1 : 0);
check(dynToBool(num) === 1 ? 1 : 0);
const zero: i32 = dynNumber(0);
check(dynToBool(zero) === 0 ? 1 : 0); // 0 is falsy

// ── string ──────────────────────────────────────────────────────────────────────────────────
const s: i32 = dynString("hi");
console.log("typeof string:", dynTypeof(s));
check(dynTypeof(s) === 4 ? 1 : 0);
check(dynStrLen(s) === 2 ? 1 : 0);
check(dynStrCharAt(s, 0) === 104 ? 1 : 0); // 'h'
check(dynStrCharAt(s, 1) === 105 ? 1 : 0); // 'i'
check(dynToBool(s) === 1 ? 1 : 0);
const empty: i32 = dynString("");
check(dynToBool(empty) === 0 ? 1 : 0); // "" is falsy

// ── object: set / get / has / overwrite / absent ──────────────────────────────────────────────
const obj: i32 = dynObject();
check(dynObjLen(obj) === 0 ? 1 : 0);
dynSet(obj, "x", dynNumber(10));
dynSet(obj, "y", dynString("hello"));
console.log("obj len:", dynObjLen(obj));
check(dynObjLen(obj) === 2 ? 1 : 0);
check(dynHas(obj, "x") === 1 ? 1 : 0);
check(dynHas(obj, "missing") === 0 ? 1 : 0);
check(dynGet(obj, "missing") === -1 ? 1 : 0);
const gx: i32 = dynGet(obj, "x");
check(dynNumberValue(gx) === 10 ? 1 : 0);
const gy: i32 = dynGet(obj, "y");
check(dynTypeof(gy) === 4 ? 1 : 0);
check(dynStrLen(gy) === 5 ? 1 : 0);
// overwrite an existing key: length stays the same, value updates
dynSet(obj, "x", dynNumber(99));
check(dynObjLen(obj) === 2 ? 1 : 0);
check(dynNumberValue(dynGet(obj, "x")) === 99 ? 1 : 0);

// ── array: push past initial capacity (forces growth → pointer write-back) ────────────────────
const arr: i32 = dynArray();
check(dynArrLen(arr) === 0 ? 1 : 0);
let i: i32 = 0;
while (i < 10) {
  dynPush(arr, dynNumber(i * 2));
  i = i + 1;
}
console.log("arr len:", dynArrLen(arr));
check(dynArrLen(arr) === 10 ? 1 : 0);
check(dynNumberValue(dynArrGet(arr, 0)) === 0 ? 1 : 0);
check(dynNumberValue(dynArrGet(arr, 9)) === 18 ? 1 : 0);
check(dynNumberValue(dynArrGet(arr, 5)) === 10 ? 1 : 0);

// ── strict equality (===) ─────────────────────────────────────────────────────────────────────
check(dynStrictEq(dynNumber(5), dynNumber(5)) === 1 ? 1 : 0);
check(dynStrictEq(dynNumber(5), dynNumber(6)) === 0 ? 1 : 0);
check(dynStrictEq(dynString("ab"), dynString("ab")) === 1 ? 1 : 0);
check(dynStrictEq(dynString("ab"), dynString("ac")) === 0 ? 1 : 0);
check(dynStrictEq(dynBool(1), dynBool(1)) === 1 ? 1 : 0);
check(dynStrictEq(dynNull(), dynNull()) === 1 ? 1 : 0);
check(dynStrictEq(dynNull(), dynUndefined()) === 0 ? 1 : 0); // null !== undefined
check(dynStrictEq(dynNumber(5), dynString("5")) === 0 ? 1 : 0); // different types
// object reference identity
check(dynStrictEq(obj, obj) === 1 ? 1 : 0);
check(dynStrictEq(dynObject(), dynObject()) === 0 ? 1 : 0);

// ── addition (+): numeric add and string concat ───────────────────────────────────────────────
const sum: i32 = dynAdd(dynNumber(3), dynNumber(4));
console.log("3 + 4 =", dynNumberValue(sum));
check(dynTypeof(sum) === 3 ? 1 : 0);
check(dynNumberValue(sum) === 7 ? 1 : 0);
const cat: i32 = dynAdd(dynString("foo"), dynString("bar"));
console.log("concat len:", dynStrLen(cat));
check(dynTypeof(cat) === 4 ? 1 : 0);
check(dynStrLen(cat) === 6 ? 1 : 0);
check(dynStrCharAt(cat, 0) === 102 ? 1 : 0); // 'f'
check(dynStrCharAt(cat, 3) === 98 ? 1 : 0);  // 'b'
// string + bool → "foo" + "true"
const mixed: i32 = dynAdd(dynString("v="), dynBool(1));
check(dynTypeof(mixed) === 4 ? 1 : 0);
check(dynStrLen(mixed) === 6 ? 1 : 0); // "v=true"

console.log("dynrt value-model: all checks passed");
