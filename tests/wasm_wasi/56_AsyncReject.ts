// Phase 56 / async-design.md sub-phase 13.3a — Promise.reject + rejection→exception.
// A rejected await re-throws the reason string, caught by a surrounding try/catch (reuses the
// Phase-15 exception machinery). An async function body that throws is likewise caught at the
// await site (eager execution + WASM exception propagation). (.catch / .finally are 13.3b.)

async function risky(n: i32): Promise<i32> {
  if (n < 0) {
    throw "negative input";
  }
  return n * 10;
}

async function main(): Promise<void> {
  // Explicit Promise.reject awaited inside try/catch.
  try {
    const x: i32 = await Promise.reject("boom");
    console.log("unreached:", x);
  } catch (e) {
    console.log("caught:", e);
  }

  // Async function that returns normally, then one that throws — both via await in one try.
  try {
    const ok: i32 = await risky(3);
    console.log("ok:", ok);
    const bad: i32 = await risky(-1);
    console.log("unreached:", bad);
  } catch (e) {
    console.log("caught:", e);
  }

  console.log("done");
}

main();
