// GC Part 4a — mark phase: mark reaches everything live from a root, and nothing else. Self-checks
// via trap. (Mark bit = tag bit 8; cleared between marks; the program never sees it.)
type i32 = number;
type f64 = number;
import { dynNumber, dynArray, dynPush, dynObject, dynSet, dynGcMarkClear, dynGcMark, dynGcMarkedCount, dynGcCellCount } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// reachable graph: arr = [n1, n2, n3] → 4 cells (arr + 3 numbers)
const n1: i32 = dynNumber(1);
const n2: i32 = dynNumber(2);
const n3: i32 = dynNumber(3);
const arr: i32 = dynArray();
dynPush(arr, n1);
dynPush(arr, n2);
dynPush(arr, n3);

dynGcMarkClear();
dynGcMark(arr);
check(dynGcMarkedCount() === 4 ? 1 : 0);

// an orphan cell NOT linked to arr must stay unmarked
const orphan: i32 = dynNumber(99);
dynGcMarkClear();
dynGcMark(arr);
check(dynGcMarkedCount() === 4 ? 1 : 0);

// nesting: obj = { items: arr } → reachable from obj is obj + arr + 3 numbers = 5
const obj: i32 = dynObject();
dynSet(obj, "items", arr);
dynGcMarkClear();
dynGcMark(obj);
check(dynGcMarkedCount() === 5 ? 1 : 0);

// arr is not reachable FROM-nothing: marking arr alone is still 4 (obj excluded)
dynGcMarkClear();
dynGcMark(arr);
check(dynGcMarkedCount() === 4 ? 1 : 0);

// total registry holds all 6 distinct cells (3 nums + arr + orphan + obj)
check(dynGcCellCount() === 6 ? 1 : 0);

console.log("GC Part4a mark: reachability verified");
