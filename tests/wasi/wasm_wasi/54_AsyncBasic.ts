// Phase 54 / async-design.md sub-phase 13.1a — async functions + await + Promise.resolve.
// Approach A (microtask-drain): async bodies run eagerly; await takes the settled value.
// Covers: async fn returning i32/f64, sequential awaits, await on an async call with a param,
// await Promise.resolve (i32 + f64), and an annotated `const x: T = await ...` (every declaration
// states its type since 2026-09-28; the old un-annotated form is now a compile error).
type f64 = number;
type i32 = number;

async function getN(): Promise<i32> {
  return 42;
}

async function doubleAsync(n: i32): Promise<i32> {
  return n * 2;
}

async function half(x: f64): Promise<f64> {
  return x / 2.0;
}

async function run(): Promise<void> {
  const a: i32 = await getN();
  const b: i32 = await doubleAsync(a);
  const c: i32 = await Promise.resolve(8);
  const inferred: i32 = await getN(); // annotated: every declaration states its type
  console.log("a:", a);
  console.log("b:", b);
  console.log("c:", c);
  console.log("inferred:", inferred);
  console.log("sum:", a + b + c + inferred);

  const x: f64 = await half(10.0);
  const y: f64 = await Promise.resolve(2.5); // annotated: every declaration states its type
  console.log("x:", x);
  console.log("y:", y);
  console.log("fsum:", x + y);
}

run();
