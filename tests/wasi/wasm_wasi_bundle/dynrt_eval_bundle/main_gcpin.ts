// functions-as-`any` — host pin table: a pinned handle survives collection while the host holds it.
// Creates a function via the interpreter, pins it, makes it GC-unreachable except via the pin, runs a
// collection under garbage, then calls it — a correct result proves the pin kept it alive (else its
// memory would have been reused). Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynRun, dynObject, dynArray, dynPush, dynNumber, dynNumberValue, dynApply, dynGcPin, dynGcUnpin, dynGcCollect, dynGcCheckHeap } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

function garbage(k: i32): void {
  let i: i32 = 0;
  while (i < k) {
    const n: i32 = dynNumber(i);
    i = i + 1;
  }
}

// 1. create a function value via the interpreter, pin it
const env1: i32 = dynObject();
const fn: i32 = dynRun("function dbl(x) { return x * 2; } return dbl;", env1);
const pin: i32 = dynGcPin(fn);

// 2. a second run leaves env1 + fn unreachable from every GC root EXCEPT the pin
const env2: i32 = dynObject();
const z: i32 = dynRun("let z = 5; return z;", env2);

// 3. allocate garbage + collect — fn survives ONLY because it is pinned
garbage(200);
dynGcCollect();
check(dynGcCheckHeap() === 0 ? 1 : 0);

// 4. call the pinned function: if the pin had failed, fn's memory would be reused → wrong/garbage
const args: i32 = dynArray();
dynPush(args, dynNumber(21));
const r: i32 = dynApply(fn, args);
const rv: f64 = dynNumberValue(r); // capture now — step 5's collect reclaims the (unrooted) result
check(rv === 42 ? 1 : 0);

// 5. release + collect — now collectible; integrity holds
dynGcUnpin(pin);
dynGcCollect();
check(dynGcCheckHeap() === 0 ? 1 : 0);

console.log("pin table: pinned function survived collection + called correctly =", rv);
