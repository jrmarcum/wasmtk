// Phase 48: **= exponent compound assignment
type i32 = number;
type f64 = number;

let globalX: f64 = 3.0;

function main(): void {
  let x: f64 = 2.0;
  x **= 3;
  console.log(x);  // 8

  let y: f64 = 4.0;
  y **= 0.5;
  console.log(y);  // 2

  let z: f64 = 10.0;
  const exp: f64 = 2.0;
  z **= exp;
  console.log(z);  // 100

  // module-level global
  globalX **= 2;
  console.log(globalX);  // 9
}

main();
// Expected output:
// 8
// 2
// 100
// 9
