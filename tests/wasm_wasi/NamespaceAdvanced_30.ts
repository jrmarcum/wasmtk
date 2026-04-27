// Phase 30: namespace — multiple namespaces, interaction with structs and classes
type i32 = number;
type f64 = number;

namespace Geometry {
  export function circleArea(radius: f64): f64 {
    return radius * radius * 3.141592653589793;
  }

  export function squarePerimeter(side: f64): f64 {
    return side * 4.0;
  }

  export function hypotenuse(a: f64, b: f64): f64 {
    return Math.sqrt(a * a + b * b);
  }
}

namespace Stats {
  export function clamp(val: i32, lo: i32, hi: i32): i32 {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
  }

  export function abs(n: i32): i32 {
    if (n < 0) return -n;
    return n;
  }

  export const MAX_SCORE: i32 = 100;
  export const MIN_SCORE: i32 = 0;
}

function main(): void {
  // Geometry namespace
  const area: f64 = Geometry.circleArea(2.0);
  console.log("circle area:", area);           // 12.566370614359172

  const perim: f64 = Geometry.squarePerimeter(4.0);
  console.log("square perimeter:", perim);     // 16

  const hyp: f64 = Geometry.hypotenuse(3.0, 4.0);
  console.log("hypotenuse:", hyp);             // 5

  // Stats namespace
  const clamped: i32 = Stats.clamp(150, Stats.MIN_SCORE, Stats.MAX_SCORE);
  console.log("clamped:", clamped);            // 100

  const neg: i32 = Stats.abs(-42);
  console.log("abs:", neg);                    // 42

  console.log("max:", Stats.MAX_SCORE);        // 100
  console.log("min:", Stats.MIN_SCORE);        // 0

  // Namespace values in expressions
  const doubled: f64 = Geometry.circleArea(1.0) * 2.0;
  console.log("doubled unit area:", doubled);  // 6.283185307179586

  const bounded: i32 = Stats.clamp(Stats.abs(-5) + 90, Stats.MIN_SCORE, Stats.MAX_SCORE);
  console.log("bounded:", bounded);            // 95
}

main();
