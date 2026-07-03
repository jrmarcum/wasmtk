// Phase 49: Array.prototype.concat(other)
type i32 = number;
type f64 = number;

function main(): void {
  // i32 concat
  const a: i32[] = [1, 2, 3];
  const b: i32[] = [4, 5, 6];
  const c: i32[] = a.concat(b);
  console.log(c.length);  // 6
  console.log(c[0]);      // 1
  console.log(c[5]);      // 6

  // f64 concat
  const x: f64[] = [1.5, 2.5];
  const y: f64[] = [3.5, 4.5];
  const z: f64[] = x.concat(y);
  console.log(z.length);  // 4
  console.log(z[1]);      // 2.5
  console.log(z[3]);      // 4.5

  // concat with empty
  const e: i32[] = [];
  const d: i32[] = a.concat(e);
  console.log(d.length);  // 3
}

main();
// Expected output:
// 6
// 1
// 6
// 4
// 2.5
// 4.5
// 3
