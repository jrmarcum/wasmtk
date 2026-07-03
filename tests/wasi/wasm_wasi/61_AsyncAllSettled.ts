// Phase 61 / async-design.md sub-phase 13.4b — Promise.allSettled over an array literal of promises.
// NEVER rejects: each result is a record { status, value | reason }. v1: array-LITERAL argument,
// value types i32 / f64; the result is a synthesized struct array (status: string, value: T,
// reason: string) so results[i].status / .value / .reason resolve. Access the field matching status.

async function compute(n: i32): Promise<i32> {
  return n * 10;
}

async function main(): Promise<void> {
  // Mixed fulfil / reject — allSettled collects all, never throws.
  const results = await Promise.allSettled([compute(1), Promise.reject("bad"), compute(3)]);
  console.log("len:", results.length);
  console.log("s0:", results[0].status, "v0:", results[0].value);
  console.log("s1:", results[1].status, "r1:", results[1].reason);
  console.log("s2:", results[2].status, "v2:", results[2].value);

  console.log("done");
}

main();
