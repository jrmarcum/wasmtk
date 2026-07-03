// @expect-fail: compile
// #14 Route A 2e.7b — the `var`→`let` gate HARD-ERRORS on an unsafe `var` (it never silently rewrites).
// Here `x` is declared inside the `if` block but read AFTER it closes — a `var` function-scope leak.
// Rewriting to `let` would make `return x` a ReferenceError, so the gate refuses to auto-repair and fails
// compilation with a precise diagnostic. Exercises the UNSAFE (hard-error) path: block-escape.
function f(): number {
  if (true) {
    var x: number = 5;
  }
  return x;
}
console.log(`${f()}`);
