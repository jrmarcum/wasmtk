// Phase 51.2 — Object spread { ...base, k: v }
// Result is a new struct: fields copied from the base, then overrides applied.
type i32 = number;
type f64 = number;

interface Point {
  x: i32;
  y: i32;
}

interface Box {
  w: f64;
  h: f64;
  label: i32;
}

// Module-level spread with a literal override.
const p1: Point = { x: 10, y: 20 };
const p2: Point = { ...p1, x: 99 };
console.log("p1.x:", p1.x); // 10
console.log("p1.y:", p1.y); // 20
console.log("p2.x:", p2.x); // 99 (overridden)
console.log("p2.y:", p2.y); // 20 (copied from p1)

// Override with a runtime variable.
const nx: i32 = 42;
const p3: Point = { ...p1, x: nx };
console.log("p3.x:", p3.x); // 42
console.log("p3.y:", p3.y); // 20

// Pure copy (no overrides).
const p4: Point = { ...p2 };
console.log("p4.x:", p4.x); // 99
console.log("p4.y:", p4.y); // 20

// Mixed i32 / f64 fields, override an f64 field.
const b1: Box = { w: 3.5, h: 4.0, label: 7 };
const b2: Box = { ...b1, h: 9.5 };
console.log("b2.w:", b2.w);         // 3.5 (copied)
console.log("b2.h:", b2.h);         // 9.5 (overridden)
console.log("b2.label:", b2.label); // 7 (copied)

// Spread inside a function body.
function shift(base: Point, dx: i32, dy: i32): i32 {
  const moved: Point = { ...base, x: base.x + dx, y: base.y + dy };
  return moved.x + moved.y;
}
console.log("shift:", shift(p1, 5, 3)); // (10+5)+(20+3) = 38

// Chained spread (spread of a spread result).
const b3: Box = { ...b2, label: 100 };
console.log("b3.w:", b3.w);         // 3.5
console.log("b3.h:", b3.h);         // 9.5
console.log("b3.label:", b3.label); // 100
