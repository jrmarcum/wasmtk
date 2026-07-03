// Phase 33 — Intersection types: function parameter and return access
type i32 = number;
type f64 = number;

interface Position { px: i32; py: i32; }
interface Velocity { vx: f64; vy: f64; }
type Entity = Position & Velocity;

function printEntity(e: Entity): void {
  console.log("px:", e.px);
  console.log("py:", e.py);
  console.log("vx:", e.vx);
  console.log("vy:", e.vy);
}

function sumCoords(e: Entity): i32 {
  return e.px + e.py;
}

const e: Entity = { px: 5, py: 10, vx: 1.5, vy: -2.0 };
printEntity(e);         // px: 5 / py: 10 / vx: 1.5 / vy: -2
console.log(sumCoords(e)); // 15
console.log(e.px);      // 5
