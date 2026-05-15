// Phase 49: combined test
type i32 = number;
type f64 = number;

interface Point {
  x: i32;
  y: i32;
}

function isPos(x: i32): boolean {
  return x > 0;
}

function double(x: i32): i32 {
  return x * 2;
}

function main(): void {
  // str.at()
  const s: string = "hello";
  console.log(s.at(0));    // h
  console.log(s.at(-1));   // o

  // Array concat
  const a: i32[] = [1, 2, 3];
  const b: i32[] = [4, 5];
  const c: i32[] = a.concat(b);
  console.log(c.length);   // 5
  console.log(c[4]);       // 5

  // Chained methods
  const nums: i32[] = [-2, 1, 3, -4, 5];
  const r: i32[] = nums.filter(isPos).map(double);
  console.log(r.length);   // 3
  console.log(r[0]);       // 2
  console.log(r[2]);       // 10

  // Optional chaining on non-nullable (strip)
  const pt: Point = { x: 10, y: 20 };
  console.log(pt?.x);      // 10
  console.log(pt?.y);      // 20
}

main();
// Expected output:
// h
// o
// 5
// 5
// 3
// 2
// 10
// 10
// 20
