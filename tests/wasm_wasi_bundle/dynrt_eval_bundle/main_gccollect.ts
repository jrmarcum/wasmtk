// GC Part 5a — mark-sweep collect: dynGcCollect() reclaims unmarked CELLS into dynrt's recycling free
// list; live values survive; reclaimed blocks are reused by later allocations. Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynNumber, dynObject, dynSet, dynGet, dynNumberValue, dynGcCellCount, dynGcCollect, dynGcFreeCount, dynGcPushRoot, dynGcPopRoot } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// a live value held in env `e`
const e: i32 = dynObject();
dynSet(e, "keep", dynNumber(42));

// build garbage: orphan number cells reachable from no root
function makeGarbage(k: i32): void {
  let i: i32 = 0;
  while (i < k) {
    const g: i32 = dynNumber(i);
    i = i + 1;
  }
}
makeGarbage(50);

const before: i32 = dynGcCellCount();
dynGcPushRoot(e); // root the live env so it (and "keep") survive
const freed: i32 = dynGcCollect();
dynGcPopRoot();
const after: i32 = dynGcCellCount();

check(freed > 0 ? 1 : 0);                  // reclaimed something
check(after === before - freed ? 1 : 0);   // registry compacted by exactly `freed`
check(dynGcFreeCount() === freed ? 1 : 0); // freed cells are on the recycle list
check(dynNumberValue(dynGet(e, "keep")) === 42 ? 1 : 0); // live value survived intact

// REUSE: new cell allocations consume the recycle list before bumping fresh memory
makeGarbage(30);
check(dynGcFreeCount() === freed - 30 ? 1 : 0); // 30 blocks reused, not freshly allocated

console.log("GC Part5a collect: reclaimed", freed, "cells; live survived; reuse verified");
