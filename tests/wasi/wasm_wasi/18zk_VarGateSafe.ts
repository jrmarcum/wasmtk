// #14 Route A 2e.7b — the `var`→`let` consumption gate auto-repairs provably-safe `var` to `let`.
// All three `var`s below are safe (no block-escape / use-before-declaration / redeclaration / loop-closure
// capture), so the gate rewrites them to `let` and the program compiles + runs identically. Exercises the
// SAFE (auto-repair) path of the gate. Output must match between run-ts and run-wasm (→ 110).
function compute(): number {
  var total: number = 0;
  for (var i: number = 0; i < 5; i = i + 1) {
    total = total + i;
  }
  if (total > 5) {
    var bonus: number = 100;
    total = total + bonus;
  }
  return total;
}
console.log(`Result: ${compute()}`);
