// @allow-output-diff: float formatting precision (e.g. Math.SQRT2 prints 15 dp vs TS 17 sig digits) — accepted limitation
type i32 = number;

export function _start(): void {
  // Constants
  console.log(Math.PI);          // 3.141592653589793
  console.log(Math.E);           // 2.718281828459045
  console.log(Math.SQRT2);       // 1.4142135623730951

  // f64 single-arg intrinsics
  console.log(Math.sqrt(9.0));   // 3
  console.log(Math.floor(2.9));  // 2
  console.log(Math.ceil(2.1));   // 3
  console.log(Math.trunc(3.7));  // 3
  console.log(Math.round(2.5));  // 3  (round-half-away-from-zero, matches JS)

  // abs — f64 context
  console.log(Math.abs(-4.5));   // 4.5

  // abs — i32 context
  const n: i32 = -7;
  const absN: i32 = Math.abs(n);
  console.log(absN);             // 7

  // min / max — f64
  console.log(Math.min(3.0, 5.0));  // 3
  console.log(Math.max(3.0, 5.0));  // 5

  // min / max — i32
  const a: i32 = 10;
  const b: i32 = 20;
  const lo: i32 = Math.min(a, b);
  const hi: i32 = Math.max(a, b);
  console.log(lo);   // 10
  console.log(hi);   // 20

  // pow
  console.log(Math.pow(2.0, 10.0));  // 1024

  // sign
  console.log(Math.sign(-3.0));   // -1
  console.log(Math.sign(0.0));    //  0
  console.log(Math.sign(5.0));    //  1

  // hypot
  console.log(Math.hypot(3.0, 4.0));  // 5

  // clz32
  const clz: i32 = Math.clz32(1);
  console.log(clz);   // 31

  // imul
  const prod: i32 = Math.imul(6, 7);
  console.log(prod);  // 42
}

_start();