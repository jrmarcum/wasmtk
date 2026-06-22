// GC Part 1 — auto-grow heap: deep interpreter recursion that previously overflowed the fixed ~2-page
// heap (fib(10) ≈ 177 calls overflowed) now runs because $__malloc grows memory on demand. Still
// passes with the GC Part 3 cell registry active (every cell tracked) thanks to the merge mutable-
// global preservation fix.
type i32 = number;
type f64 = number;
import { dynRun, dynObject, dynNumberValue } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

const e: i32 = dynObject();
const r: i32 = dynRun("function fib(n){if(n<2){return n;}return fib(n-1)+fib(n-2);} return fib(15);", e);
console.log("fib(15) =", dynNumberValue(r));
check(dynNumberValue(r) === 610 ? 1 : 0);
console.log("GC Part1 auto-grow: deep recursion passed");
