type i32 = number;
type f64 = number;

function addOptional(a: i32, b?: i32): i32 {
  if (b === undefined) {
    b = 0;
  }
  return a + b;
}

function offset(x: f64, dx?: f64, dy?: f64): f64 {
  if (dx === undefined) {
    dx = 0;
  }
  if (dy === undefined) {
    dy = 0;
  }
  return x + dx + dy;
}

function build(base: i32, step?: i32, count: i32 = 3): i32 {
  if (step === undefined) {
    step = 0;
  }
  return base + step * count;
}

export function _start(): void {
  console.log(addOptional(7));       // 7
  console.log(addOptional(7, 3));    // 10
  console.log(offset(10.0));         // 10
  console.log(offset(10.0, 1.5));    // 11.5
  console.log(build(10));            // 10
  console.log(build(10, 2));         // 16
}

_start();
