// Phase 36 — Simple conditional types: generic conditional type as variable annotation
type i32 = number;
type f64 = number;

// Toggle: if T is i32 → f64; otherwise → i32
type Toggle<T> = T extends i32 ? f64 : i32;

function main(): void {
  const a: Toggle<i32> = 3.5;    // Toggle<i32> → f64  (i32 extends i32 → true  → f64)
  const b: Toggle<f64> = 10;     // Toggle<f64> → i32  (f64 extends i32 → false → i32)
  const c: Toggle<string> = 7;   // Toggle<string> → i32 (string extends i32 → false → i32)

  console.log("a:", a);   // a: 3.5
  console.log("b:", b);   // b: 10
  console.log("c:", c);   // c: 7
}

main();
