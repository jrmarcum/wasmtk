// Phase 58 / async-design.md sub-phase 13.1b — promise-holding-var inner-type tracking.
// A local that holds a promise (`const p = asyncFn();`) is tracked so `await p` picks the right
// $__promise_await_<T> (i32 vs f64) and `p.then(cb)` is recognized as a promise. Aliasing
// (`const q = p`) carries the tracking for free. (Callbacks are still NAMED functions.)

async function compute(n: i32): Promise<i32> {
  return n * 100;
}
async function computeF(x: f64): Promise<f64> {
  return x + 0.5;
}
function dbl(v: i32): i32 {
  return v * 2;
}

async function main(): Promise<void> {
  // Promise held in a var, then awaited.
  const p = compute(3);
  const v: i32 = await p;
  console.log("v:", v);

  // f64 promise var — verifies await_f64 is picked from the tracked inner type, not the i32 default.
  const pf = computeF(2.0);
  const vf: f64 = await pf;
  console.log("vf:", vf);

  // .then on a promise var (isPromiseExpr resolves the bare receiver via the side table).
  const p2 = compute(5);
  const w: i32 = await p2.then(dbl);
  console.log("w:", w);

  // Aliasing: q inherits p3's promise tracking.
  const p3 = compute(7);
  const q = p3;
  const z: i32 = await q;
  console.log("z:", z);

  console.log("done");
}

main();
