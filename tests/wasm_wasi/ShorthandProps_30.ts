// Phase 30: shorthand property notation in struct literals and returns
type i32 = number;
type f64 = number;

interface Vec2 {
  x: f64;
  y: f64;
}

interface Rect {
  width: i32;
  height: i32;
}

function makeVec(x: f64, y: f64): Vec2 {
  return { x, y };
}

function makeRect(width: i32, height: i32): Rect {
  return { width, height };
}

function scaleVec(v: Vec2, factor: f64): Vec2 {
  const x: f64 = v.x * factor;
  const y: f64 = v.y * factor;
  return { x, y };
}

function main(): void {
  // Shorthand in function return
  const v: Vec2 = makeVec(3.0, 4.0);
  console.log("x:", v.x);      // 3
  console.log("y:", v.y);      // 4

  const r: Rect = makeRect(10, 20);
  console.log("width:", r.width);   // 10
  console.log("height:", r.height); // 20

  const v2: Vec2 = scaleVec(v, 2.0);
  console.log("scaled x:", v2.x);   // 6
  console.log("scaled y:", v2.y);   // 8
}

main();
