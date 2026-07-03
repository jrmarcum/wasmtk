// deno-fmt-ignore-file
// Compiler-gap regression (2026-06-30): Gap 3 — a `const` nested in a block on a SINGLE physical
// line function body must be declared as a WAT local (else "local $x cannot be resolved").
type i32 = number;
type f64 = number;
function check(c: i32, base: i32): void { if (c === 0) { const x: i32 = base * 2; const y: i32 = x + 1; console.log(y); } else { const z: f64 = 3.5; console.log(z); } }
check(0, 10); // 21
check(9, 0);  // 3.5
