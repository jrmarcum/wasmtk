// Phase 48: object destructuring with defaults
// Note: defaults apply when the field value is zero (wasic semantics — see CLAUDE.md)
type i32 = number;
type f64 = number;

interface Vec2 {
  x: f64;
  y: f64;
}

interface Counter {
  a: i32;
  b: i32;
}

function main(): void {
  // x has a value, y is 0 → default used for y
  const v: Vec2 = { x: 3.5, y: 0.0 };
  const { x = 1.0, y = 2.0 } = v;
  console.log(x);  // 3.5
  console.log(y);  // 2

  // a has a value, b is 0 → default used for b
  const p: Counter = { a: 5, b: 0 };
  const { a = 10, b = 20 } = p;
  console.log(a);  // 5
  console.log(b);  // 20

  // renamed destructuring with default
  const q: Counter = { a: 0, b: 7 };
  const { a: qa = 100, b: qb = 200 } = q;
  console.log(qa);  // 100 (a was 0)
  console.log(qb);  // 7
}

main();
// Expected output:
// 3.5
// 2
// 5
// 20
// 100
// 7
