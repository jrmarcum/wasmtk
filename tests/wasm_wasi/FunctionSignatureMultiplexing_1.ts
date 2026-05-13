// Core_TypeMultiplex.ts
type i32 = number;
type f64 = number;

// Signature A: (i32, i32) -> i32
function add(a: i32, b: i32): i32 { return a + b; }

// Signature B: (f64) -> f64
function square(n: f64): f64 { return n * n; }

// Signature C: (i32, f64, i32) -> f64
function complex(a: i32, b: f64, c: i32): f64 {
  return (b * b) + (a as f64) + (c as f64);
}

export function _start(): void {
  console.log(add(1, 2));
  console.log(square(3.0));
  console.error(complex(1, 2.0, 3));
}

_start();