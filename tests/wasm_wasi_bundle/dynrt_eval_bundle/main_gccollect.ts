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
check(after === before - freed ? 1 : 0);   // registry compacted by exactly `freed` cells
// each reclaimed number cell also frees its Float64Array payload, so the recycle list holds at least
// `freed` blocks (cells + payloads)
const freeAfterCollect: i32 = dynGcFreeCount();
check(freeAfterCollect >= freed ? 1 : 0);
check(dynNumberValue(dynGet(e, "keep")) === 42 ? 1 : 0); // live value survived intact

// REUSE: new allocations consume the recycle list before bumping fresh memory
makeGarbage(30);
check(dynGcFreeCount() < freeAfterCollect ? 1 : 0); // recycled blocks were reused, not freshly bumped

console.log("GC Part5 collect: reclaimed", freed, "cells (+payloads); live survived; reuse verified");
