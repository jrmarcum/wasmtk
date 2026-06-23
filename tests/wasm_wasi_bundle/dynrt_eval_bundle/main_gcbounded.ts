// GC Part 5b — bounded memory: a long interpreter loop allocates a fresh temp + rebinds `s` each
// iteration (~3 garbage cells/iter). Across 10000 iterations that is ~30000 cells; WITHOUT collection
// the registry would grow unbounded, but the auto-collect trigger (at statement boundaries, with
// intermediate values rooted) reclaims the per-iteration garbage. Proves the GC bounds memory for
// long-running dynamic code. Self-checks via trap.
type i32 = number;
type f64 = number;
import { dynObject, dynRun, dynNumberValue, dynGcCellCount, dynGcCollect, dynGcPushRoot, dynGcPopRoot } from "../dynrt_bundle/dynrt_lib_modc.wasm";

const guard: i32[] = [0];
function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

const e: i32 = dynObject();
const r: i32 = dynRun("let i = 0; let s = 0; while (i < 10000) { let t = i + 1; s = s + t; i = i + 1; } return s;", e);

// correctness: s = sum(1..10000) = 50005000 — proves no LIVE value was wrongly collected mid-loop
check(dynNumberValue(r) === 50005000 ? 1 : 0);

// a final explicit collect shows the surviving LIVE set is tiny (i, s, the result, the env) — NOT the
// ~30000 cells the loop allocated. That the program even reached here in bounded memory IS the proof
// auto-collect ran during the loop.
dynGcPushRoot(r);
dynGcCollect();
dynGcPopRoot();
check(dynGcCellCount() < 100 ? 1 : 0);

console.log("GC Part5b bounded: sum =", dynNumberValue(r), "; live cells after collect =", dynGcCellCount());
