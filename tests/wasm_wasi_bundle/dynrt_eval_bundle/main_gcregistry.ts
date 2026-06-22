// GC Part 3 — cell registry: every boxed value cell is recorded in a registry list so a future
// mark-sweep (P4/P5) can enumerate all allocations. Verifies dynGcCellCount() tracks each allocation
// and scales (20000 cells) without corruption — the regression that surfaced the merge mutable-global
// preservation fix (a 0-sentinel registry ptr was being clobbered to 131072). Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynNumber, dynString, dynArray, dynGcCellCount } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// each constructor allocates exactly one value cell → the registry count rises by one per call
const before: i32 = dynGcCellCount();
const a: i32 = dynNumber(1);
const b: i32 = dynNumber(2);
const s: i32 = dynString("hi");
const arr: i32 = dynArray();
check(dynGcCellCount() - before === 4 ? 1 : 0);

// scale: allocate many cells; the registry (a self-managed doubling list) must track them all
function bulk(n: i32): void {
  let i: i32 = 0;
  while (i < n) {
    const v: i32 = dynNumber(i);
    i = i + 1;
  }
}
const c0: i32 = dynGcCellCount();
bulk(20000);
check(dynGcCellCount() - c0 === 20000 ? 1 : 0);

console.log("GC Part3 cell registry: tracked", dynGcCellCount(), "cells");
