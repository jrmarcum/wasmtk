// numbertypes.js — functions typed with `number` in .d.ts (maps to f64)

export function area(w, h) {
  return w * h;
}

export function perimeter(w, h) {
  return 2.0 * (w + h);
}

export function hypotenuse(a, b) {
  return Math.sqrt(a * a + b * b);
}
