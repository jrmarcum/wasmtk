type i32 = number;
type f64 = number;

// Default i32 parameter
function add(a: i32, b: i32 = 10): i32 {
  return a + b;
}

// Default f64 parameter
function scale(val: f64, factor: f64 = 2.5): f64 {
  return val * factor;
}

// Multiple defaults
function clamp(val: i32, lo: i32 = 0, hi: i32 = 100): i32 {
  if (val < lo) return lo;
  if (val > hi) return hi;
  return val;
}

export function _start(): void {
  console.log(add(5));        // 15  (b defaults to 10)
  console.log(add(5, 3));     // 8   (explicit b)
  console.log(scale(4.0));    // 10  (factor defaults to 2.5)
  console.log(scale(4.0, 3.0)); // 12
  console.log(clamp(50));     // 50  (within default 0–100)
  console.log(clamp(150));    // 100 (clamped to hi default)
  console.log(clamp(-5));     // 0   (clamped to lo default)
}

_start();
