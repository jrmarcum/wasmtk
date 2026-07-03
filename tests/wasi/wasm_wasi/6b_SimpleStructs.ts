type i32 = number;
type f64 = number;

interface Vec2 {
  x: f64;
  y: f64;
}

interface Particle {
  mass: f64;
  charge: i32;
  active: i32;
}

function magnitude(v: Vec2): f64 {
  return Math.sqrt(v.x * v.x + v.y * v.y);
}

function isActive(p: Particle): i32 {
  return p.active;
}

export function _start(): void {
  // Static struct literal
  const v: Vec2 = { x: 3.0, y: 4.0 };
  console.log(v.x);             // 3
  console.log(v.y);             // 4
  console.log(magnitude(v));    // 5

  // Field write
  v.x = 6.0;
  v.y = 8.0;
  console.log(v.x);             // 6
  console.log(magnitude(v));    // 10

  // Mixed-type struct
  const p: Particle = { mass: 9.109e-31, charge: -1, active: 1 };
  console.log(p.charge);        // -1
  console.log(p.active);        //  1
  console.log(isActive(p));     //  1

  // Disable particle
  p.active = 0;
  console.log(isActive(p));     //  0

  // Template literal with struct field
  console.log(`x=${v.x} y=${v.y}`);  // x=6 y=8
}

_start();
