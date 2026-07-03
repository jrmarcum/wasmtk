// Phase 39 — combined: realistic jstyper-converted utility functions
// Covers i32, f64, bool, recursive functions, loops — all converted from JS-style bodies
type i32 = number;
type f64 = number;
type bool = boolean;

function factorial(n: i32): i32 {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
}

function isPrime(n: i32): bool {
  if (n < 2) return false;
  let i: i32 = 2;
  while (i * i <= n) {
    if (n % i === 0) return false;
    i = i + 1;
  }
  return true;
}

function average(a: f64, b: f64, c: f64): f64 {
  return (a + b + c) / 3.0;
}

function gcd(a: i32, b: i32): i32 {
  while (b !== 0) {
    const t: i32 = b;
    b = a % b;
    a = t;
  }
  return a;
}

function lerp(a: f64, b: f64, t: f64): f64 {
  return a + (b - a) * t;
}

console.log(factorial(5));              // 120
console.log(factorial(0));              // 1
console.log(factorial(1));              // 1
console.log(isPrime(7));               // true
console.log(isPrime(10));              // false
console.log(isPrime(2));               // true
console.log(average(1.0, 2.0, 3.0));  // 2
console.log(gcd(48, 18));             // 6
console.log(gcd(100, 75));            // 25
console.log(lerp(0.0, 10.0, 0.5));   // 5
console.log(lerp(0.0, 100.0, 0.25)); // 25
