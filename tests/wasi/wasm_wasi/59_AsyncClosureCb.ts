// Phase 59 / async-design.md sub-phase 13.1b — capturing-closure callbacks for .then / .finally.
// A capturing arrow (`v => base + v`) lifts to a closure struct; the reaction record stores the
// closure ptr (env) and the trampoline dispatches via call_indirect through it. Covers a capturing
// .then fulfill cb (i32 + f64) and a capturing .finally cb. (Capturing .catch needs a string-param
// closure, which wasic's closure trampoline can't expand to ptr+len — use a named recover, e.g. 57.)

async function compute(n: i32): Promise<i32> {
  return n * 10;
}

async function main(): Promise<void> {
  const base: i32 = 100;
  // Capturing fulfill callback (i32).
  const a: i32 = await compute(2).then((v: i32) => base + v);
  console.log("a:", a);

  // Capturing finally callback — reads a captured value (its return is ignored), value passes through.
  const label: i32 = 42;
  const c: i32 = await compute(5).finally(() => label);
  console.log("c:", c);

  // Capturing fulfill callback (f64).
  const bias: f64 = 0.25;
  const d: f64 = await Promise.resolve(1.5).then((v: f64) => v + bias);
  console.log("d:", d);

  console.log("done");
}

main();
