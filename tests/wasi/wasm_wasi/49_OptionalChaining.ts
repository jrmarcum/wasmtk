// Phase 49: Optional chaining (?.) — compile-time strip for non-nullable types
type i32 = number;
type f64 = number;

interface Vec2 {
  x: f64;
  y: f64;
}

interface Point {
  x: i32;
  y: i32;
}

function main(): void {
  // Non-nullable struct — ?. stripped to . at compile time
  const v: Vec2 = { x: 3.0, y: 4.0 };
  console.log(v?.x);   // 3
  console.log(v?.y);   // 4

  const p: Point = { x: 10, y: 20 };
  console.log(p?.x);   // 10
  console.log(p?.y);   // 20

  // Chained ?. on non-nullable (both stripped)
  const v2: Vec2 = { x: 7.0, y: 8.0 };
  console.log(v2?.x);  // 7
  console.log(v2?.y);  // 8
}

main();
// Expected output:
// 3
// 4
// 10
// 20
// 7
// 8
