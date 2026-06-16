// Phase 57 / async-design.md sub-phase 13.3b — .catch / .finally rejection reactions.
// .catch(onR) recovers a rejected promise to a value (onR takes the string reason); on a
// fulfilled promise it passes the value through (onR is NOT called). .finally(onFin) runs on
// both settle paths and passes the original settlement through unchanged. .then(onF).catch(onR)
// chains a fulfill reaction then a recovery. All reactions run as microtasks (FIFO), so callbacks
// fire after the current synchronous run. (Reuses the 13.2 microtask queue + 13.3a rejection.)

function recover(e: string): i32 {
  console.log("recovered from:", e);
  return -1;
}
function dbl(v: i32): i32 {
  return v * 2;
}
function mark(): void {
  console.log("finally");
}

async function main(): Promise<void> {
  // .catch on a rejected promise → recovery value (onR called with the reason).
  const a: i32 = await Promise.reject("rejA").catch(recover);
  console.log("a:", a);

  // .catch on a fulfilled promise → passthrough (onR NOT called).
  const b: i32 = await Promise.resolve(7).catch(recover);
  console.log("b:", b);

  // .finally on the fulfilled path → onFin runs, the value passes through.
  const c: i32 = await Promise.resolve(5).finally(mark);
  console.log("c:", c);

  // .then(onF).catch(onR): fulfilled → dbl runs, .catch passes the value through.
  const d: i32 = await Promise.resolve(4).then(dbl).catch(recover);
  console.log("d:", d);

  console.log("done");
}

main();
