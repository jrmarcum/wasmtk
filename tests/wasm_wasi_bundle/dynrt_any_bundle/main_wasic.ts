// Driver for #14.3.1 — the wasic `any` type + auto-merge foundation.
//
// This file uses the `any` type, so the compiler AUTO-MERGES the own dynamic runtime
// (`wasmtk:dynrt`) — no explicit import needed (the bundler injects it on `any`/`eval` usage). An
// `any` value is a boxed dynrt handle (lowered to i32); the dynrt ops (dynNumber/dynNumberValue/
// dynEval/dynString/dynTypeof/…) are available by name via the injected import. This first slice
// proves the type + auto-merge + box/unbox ROUND-TRIP end to end; implicit boxing at declarations
// and `as`-unboxing are the next 3.1 slices.
//
// Self-checking: each expectation calls check(); on the first failure check() reads far out of
// bounds, trapping the module (nonzero exit), so a successful `run` proves it.

type i32 = number;
type f64 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000]; // force a WebAssembly trap → nonzero exit
    console.log(x);
  }
}

// `any` value = a boxed dynrt handle (i32). Box a number, unbox it.
const boxed: any = dynNumber(42);
check(dynNumberValue(boxed) === 42 ? 1 : 0);

// `any` from eval — runtime code from a string, result is an any handle.
const evaled: any = dynEval("6 * 7");
check(dynNumberValue(evaled) === 42 ? 1 : 0);

// `any` string + introspection.
const str: any = dynString("hi");
check(dynTypeof(str) === 4 ? 1 : 0); // 4 = string
check(dynStrLen(str) === 2 ? 1 : 0);

// `any` bool + truthiness.
const flag: any = dynBool(1);
check(dynToBool(flag) === 1 ? 1 : 0);

// pass an `any` to a function and back (param/return type `any` = i32 handle)
function pickFirst(a: any, b: any): any {
  return a;
}
const chosen: any = pickFirst(boxed, evaled);
check(dynNumberValue(chosen) === 42 ? 1 : 0);

// ── 3.1-sugar: implicit boxing of literal initialisers + `as`-unboxing ────────────────────────
const num: any = 42; // implicitly → dynNumber(42)
const ni: i32 = num as i32; // unbox → dynNumberValue + trunc
check(ni === 42 ? 1 : 0);
const nf: f64 = num as f64; // unbox → dynNumberValue
check(nf === 42 ? 1 : 0);

const pi: any = 3.5; // implicit f64 box
const pf: f64 = pi as f64;
check(pf === 3.5 ? 1 : 0);
const pit: i32 = pi as i32; // truncates
check(pit === 3 ? 1 : 0);

const txt: any = "hello"; // implicitly → dynString("hello")
check(dynTypeof(txt) === 4 ? 1 : 0);
check(dynStrLen(txt) === 5 ? 1 : 0);

const yes: any = true; // implicitly → dynBool(1)
const yb: bool = yes as bool; // unbox → dynToBool
check(yb === 1 ? 1 : 0);
const no: any = false;
const nb: bool = no as bool;
check(nb === 0 ? 1 : 0);

console.log("dynrt any foundation: all checks passed");
