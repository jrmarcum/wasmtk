// Phase 39 — jstyper number→f64 mapping output
// Represents typed .ts produced by: wasmtk jstyper numbertypes.js
// (numbertypes.d.ts uses `number` type which jstyper maps to f64)
type f64 = number;

export function area(w: f64, h: f64): f64 {
  return w * h;
}

export function perimeter(w: f64, h: f64): f64 {
  return 2.0 * (w + h);
}

export function hypotenuse(a: f64, b: f64): f64 {
  return Math.sqrt(a * a + b * b);
}

console.log(area(3.0, 4.0));           // 12
console.log(perimeter(3.0, 4.0));      // 14
console.log(hypotenuse(3.0, 4.0));     // 5
