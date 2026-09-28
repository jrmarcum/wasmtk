// @expect-fail: compile, run-ts
// Regression (2026-09-28, H12): calling a method on an undeclared receiver must fail the compile
// through a DIAGNOSTIC, not by the transpiler calling rt.exit(1) from inside itself (which killed
// the host process, including hybrid/dync probe compiles). The abort is still loud: exit non-zero.
// run-ts fails too, correctly: natively this is a ReferenceError (exit 1).
type i32 = number;

function main(): i32 {
  const n: i32 = 4;
  undeclaredThing.doWork(n);
  return n;
}

console.log(main());
