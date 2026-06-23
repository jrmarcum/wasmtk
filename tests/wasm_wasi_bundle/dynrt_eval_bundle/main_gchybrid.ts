// GC hybrid allocator — stress + integrity. Exercises the path that broke coalesce-on-free
// (makeNums + collect → proactive defrag mid-sweep) plus mixed-size build/drop/collect cycles
// (Tier 2 + on-demand defrag), and after EVERY phase asserts dynGcCheckHeap()===0 (no cycle, sizes
// valid, free counters consistent). Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynNumber, dynArray, dynPush, dynArrLen, dynGcCollect, dynGcCheckHeap, dynGcCellCount } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

function makeNums(k: i32): void {
  let i: i32 = 0;
  while (i < k) {
    const n: i32 = dynNumber(i);
    i = i + 1;
  }
}

function buildLen(n: i32): i32 {
  const a: i32 = dynArray();
  let i: i32 = 0;
  while (i < n) {
    dynPush(a, dynNumber(i));
    i = i + 1;
  }
  return dynArrLen(a); // a is local → collectible after return
}

// Phase 1: heavy small-allocation + collect (frees ~4000 blocks → proactive defrag fires mid-sweep)
makeNums(2000);
check(dynGcCheckHeap() === 0 ? 1 : 0);
dynGcCollect();
check(dynGcCheckHeap() === 0 ? 1 : 0);

// Phase 2: mixed-size build/drop/collect cycles (Tier 2 churn + large-list requests + on-demand defrag)
let c: i32 = 0;
let ok: i32 = 1;
while (c < 25) {
  if (buildLen(200) !== 200) ok = 0;
  dynGcCollect();
  check(dynGcCheckHeap() === 0 ? 1 : 0);
  c = c + 1;
}
check(ok);

// memory stays bounded
check(dynGcCellCount() < 100 ? 1 : 0);

console.log("GC hybrid: integrity OK across stress + defrag; checkHeap =", dynGcCheckHeap(), "live =", dynGcCellCount());
