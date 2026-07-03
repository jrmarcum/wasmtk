// GC polish — free-list splitting: dynAlloc carves the remainder off an oversized reused block so the
// leftover bytes are recycled, not lost. This driver forces the split path: it builds + drops large
// arrays (large element-list blocks) interleaved with many small number cells, collecting between, so
// small allocations must reuse + SPLIT the freed large blocks. Verifies correctness survives the
// split-heavy reuse and that memory stays bounded. Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynNumber, dynNumberValue, dynArray, dynPush, dynArrGet, dynArrLen, dynGcCollect, dynGcCellCount } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// Build an array of 0..n-1; return 1 if length + first/last elements are correct, else 0. `a` is local
// → collectible after return.
function buildCheck(n: i32): i32 {
  const a: i32 = dynArray();
  let i: i32 = 0;
  while (i < n) {
    dynPush(a, dynNumber(i));
    i = i + 1;
  }
  const lenOk: i32 = dynArrLen(a) === n ? 1 : 0;
  const first: f64 = dynNumberValue(dynArrGet(a, 0));
  const last: f64 = dynNumberValue(dynArrGet(a, n - 1));
  const lastExp: f64 = n - 1;
  const valOk: i32 = first === 0.0 ? (last === lastExp ? 1 : 0) : 0;
  return lenOk === 1 ? valOk : 0;
}

check(buildCheck(100) === 1 ? 1 : 0); // first build + correctness
dynGcCollect();                       // frees the large array + list block into the free list

// many cycles: each builds + drops a large array; subsequent allocs reuse + split the recycled blocks.
let c: i32 = 0;
let ok: i32 = 1;
while (c < 30) {
  if (buildCheck(100) !== 1) ok = 0;
  dynGcCollect();
  c = c + 1;
}
check(ok);
check(dynGcCellCount() < 50 ? 1 : 0); // bounded — everything reclaimed + recycled (incl. split leftovers)

console.log("GC split: correctness + bounded under mixed-size reuse; live cells =", dynGcCellCount());
