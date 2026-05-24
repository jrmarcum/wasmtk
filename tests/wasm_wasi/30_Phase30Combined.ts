// Phase 30: combined — namespace + interface inheritance + shorthand props
type i32 = number;
type f64 = number;

// --- Namespace ---
namespace Vector {
  export function dot(ax: f64, ay: f64, bx: f64, by: f64): f64 {
    return ax * bx + ay * by;
  }

  export function length(x: f64, y: f64): f64 {
    return Math.sqrt(x * x + y * y);
  }

  export const ZERO_X: f64 = 0.0;
  export const ZERO_Y: f64 = 0.0;
}

// --- Interface inheritance ---
interface Base {
  id: i32;
  weight: f64;
}

interface Particle extends Base {
  charge: i32;
}

// --- Shorthand properties ---
interface Vec2 {
  x: f64;
  y: f64;
}

function makeVec(x: f64, y: f64): Vec2 {
  return { x, y };
}

function main(): void {
  // Namespace functions
  const dp: f64 = Vector.dot(1.0, 0.0, 0.0, 1.0);
  console.log("dot product:", dp);          // 0

  const len: f64 = Vector.length(3.0, 4.0);
  console.log("length:", len);              // 5

  console.log("zero_x:", Vector.ZERO_X);   // 0
  console.log("zero_y:", Vector.ZERO_Y);   // 0

  // Interface inheritance
  const p: Particle = { id: 1, weight: 9.109, charge: -1 };
  console.log("id:", p.id);                // 1
  console.log("weight:", p.weight);        // 9.109
  console.log("charge:", p.charge);        // -1

  // Shorthand props
  const v: Vec2 = makeVec(5.0, 12.0);
  console.log("x:", v.x);                  // 5
  console.log("y:", v.y);                  // 12
  const vlen: f64 = Vector.length(v.x, v.y);
  console.log("vec length:", vlen);         // 13
}

main();
