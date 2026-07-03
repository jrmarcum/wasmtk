// Phase 51.3 — Nested tuple types, literals, destructuring, and params.
type i32 = number;
type f64 = number;

// Nested tuple as a function parameter, destructured.
function addNested([[a, b], c]: [[i32, i32], i32]): i32 {
  return a + b + c;
}

function main(): void {
  // Nested tuple literal + nested destructuring.
  const t: [[i32, i32], i32] = [[1, 2], 3];
  const [[a, b], c] = t;
  console.log("a:", a); // 1
  console.log("b:", b); // 2
  console.log("c:", c); // 3

  // Mixed f64/i32 nested tuple.
  const u: [[f64, f64], i32] = [[1.5, 2.5], 7];
  const [[ux, uy], uz] = u;
  console.log("ux:", ux); // 1.5
  console.log("uy:", uy); // 2.5
  console.log("uz:", uz); // 7

  // Flat tuple still works (regression guard).
  const p: [i32, i32] = [10, 20];
  const [px, py] = p;
  console.log("px:", px); // 10
  console.log("py:", py); // 20

  // Nested tuple passed to a destructuring param.
  console.log("addNested:", addNested(t)); // 6
}

main();
