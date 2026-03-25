type f64 = number;
export function testEqF64(a: f64, b: f64): boolean {
  return a == b;
}

export function testGtF64(a: f64, b: f64): boolean {
  return a > b;
}

export function testLtF64(a: f64, b: f64): boolean {
  return a < b;
}

// Special case: NaN comparison
// In Wasm, NaN != NaN should return true
export function testIsNaN(a: f64): boolean {
  return a != a;
}

console.log(testEqF64(1.0, 1.0)); // true
console.log(testGtF64(2.0, 1.0)); // true
console.log(testLtF64(1.0, 2.0)); // true
console.log(testIsNaN(NaN)); // true      