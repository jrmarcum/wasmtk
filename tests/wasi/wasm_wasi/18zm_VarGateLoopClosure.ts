// @expect-fail: compile
// #14 Route A 2e.7b — the `var`→`let` gate HARD-ERRORS on a loop variable captured by a closure.
// `for (var i …)` shares ONE binding across iterations (all closures see the final value); rewriting to
// `let` makes it per-iteration (a behavior change). Since the rewrite would not be behavior-preserving,
// the gate refuses to auto-repair and fails compilation. Exercises the UNSAFE path: loop-closure capture.
function build(): number {
  var fns: Array<() => number> = [];
  for (var i: number = 0; i < 3; i = i + 1) {
    fns[i] = () => i;
  }
  return fns[0]();
}
console.log(`${build()}`);
