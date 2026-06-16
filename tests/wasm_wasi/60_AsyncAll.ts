// Phase 60 / async-design.md sub-phase 13.4 — Promise.all over an array literal of promises.
// Builds a T[] of the settled values once all elements settle (drain first); the FIRST rejection
// rejects the combined promise (re-thrown by await, caught by try/catch). v1: array-LITERAL argument,
// element types i32 / f64. (Promise.allSettled is a later follow-up — needs a struct-array result.)

async function compute(n: i32): Promise<i32> {
  return n * 10;
}
async function fcompute(x: f64): Promise<f64> {
  return x * 2.0;
}
function addOne(v: i32): i32 {
  return v + 1;
}

async function main(): Promise<void> {
  // All fulfilled (i32) → i32[] of values.
  const xs: i32[] = await Promise.all([compute(1), compute(2), compute(3)]);
  console.log("xs:", xs[0], xs[1], xs[2]);
  console.log("len:", xs.length);

  // Mixed sources: Promise.resolve + async call + a pending .then (settled by the drain).
  const ys: i32[] = await Promise.all([Promise.resolve(5), compute(4), Promise.resolve(1).then(addOne)]);
  console.log("ys:", ys[0], ys[1], ys[2]);

  // f64 elements → f64[].
  const fs: f64[] = await Promise.all([fcompute(1.5), fcompute(2.5)]);
  console.log("fs:", fs[0], fs[1]);

  // First rejection → the combined promise rejects → re-thrown by await → caught.
  try {
    const zs: i32[] = await Promise.all([compute(1), Promise.reject("boom"), compute(3)]);
    console.log("unreached:", zs[0]);
  } catch (e) {
    console.log("caught:", e);
  }

  console.log("done");
}

main();
