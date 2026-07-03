// Phase 55 / async-design.md sub-phase 13.2 — Promise.then + the microtask queue.
// .then(cb) registers a reaction (per-T trampoline via call_indirect) that runs as a MICROTASK,
// so callbacks fire after the current synchronous run, in FIFO order. Covers: fire-and-forget
// .then (ordering vs sync code + FIFO), value-returning callbacks, chained .then().then(),
// f64 callbacks, and awaiting a .then result.

function triple(v: i32): i32 {
  return v * 3;
}
function addTen(v: i32): i32 {
  return v + 10;
}
function onR(v: i32): void {
  console.log("got:", v);
}
function halve(v: f64): f64 {
  return v / 2.0;
}

async function main(): Promise<void> {
  // Fire-and-forget: callbacks are microtasks → "sync" prints first, then FIFO got:10, got:20.
  Promise.resolve(10).then(onR);
  Promise.resolve(20).then(onR);
  console.log("sync");

  const x: i32 = await Promise.resolve(5).then(triple);
  console.log("x:", x);

  const y: i32 = await Promise.resolve(2).then(triple).then(addTen);
  console.log("y:", y);

  const z: f64 = await Promise.resolve(9.0).then(halve);
  console.log("z:", z);
}

main();
