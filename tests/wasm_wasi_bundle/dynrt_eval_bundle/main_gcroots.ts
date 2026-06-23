// GC Part 4b — interpreter shadow-stack: dynRun pushes/pops its scope as a GC root, so a collection
// during a (possibly nested) run sees all live scopes. Marking from roots reaches all live state.
// Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynNumber, dynArray, dynPush, dynObject, dynRun, dynGcRootCount, dynGcMarkRoots, dynGcMarkedCount, dynGcMarkClear, dynGcMark, dynGcPushRoot, dynGcPopRoot } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// (1) BALANCE: dynRun pushes its scope and pops it — incl. across nested function calls. After a
// recursive run returns, the root stack is back to empty (every push had a matching pop).
const e: i32 = dynObject();
check(dynGcRootCount() === 0 ? 1 : 0);
dynRun("function f(n){ if(n<1){ return 0; } return f(n-1); } return f(4);", e);
check(dynGcRootCount() === 0 ? 1 : 0);

// (2) DRIVER ROOTS + mark-from-roots — the mechanism P5's collect() will use. Build arr=[n1,n2,n3]
// (4 cells), push it as a root, mark roots → exactly those 4 are marked. Pop → stack empty again.
const arr: i32 = dynArray();
dynPush(arr, dynNumber(1));
dynPush(arr, dynNumber(2));
dynPush(arr, dynNumber(3));
dynGcPushRoot(arr);
check(dynGcRootCount() === 1 ? 1 : 0);
dynGcMarkRoots();
check(dynGcMarkedCount() === 4 ? 1 : 0);
dynGcPopRoot();
check(dynGcRootCount() === 0 ? 1 : 0);

// (3) CLOSURE CHAIN: a returned closure captures `cap` in its defining env. Marking the closure must
// traverse tag-7 → defEnv (an env object) → its bound values AND its parent scope (slot 2). If slot 2
// weren't followed, the enclosing env + its values would be missed. Assert deep traversal (>= 5
// cells: closure + body + params + defEnv + the captured number, at least).
const e2: i32 = dynObject();
const closure: i32 = dynRun("function outer(){ let cap = 42; function inner(){ return cap; } return inner; } return outer();", e2);
check(dynGcRootCount() === 0 ? 1 : 0);
dynGcMarkClear();
dynGcMark(closure);
check(dynGcMarkedCount() >= 5 ? 1 : 0);

console.log("GC Part4b shadow-stack: roots verified");
