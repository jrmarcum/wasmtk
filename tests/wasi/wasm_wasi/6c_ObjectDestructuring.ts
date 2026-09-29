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

// Struct param destructuring
function sumCoords(v: Vec2): f64 {
  const { x, y }: Vec2 = v;
  return x + y;
}

// Renamed destructuring from param
function chargeSign(p: Particle): i32 {
  const { charge: c }: Particle = p;
  if (c < 0) return -1;
  if (c > 0) return 1;
  return 0;
}

export function _start(): void {
  // Basic destructuring from local struct
  const v: Vec2 = { x: 3.0, y: 4.0 };
  const { x, y }: Vec2 = v;
  console.log(x);           // 3
  console.log(y);           // 4

  // Renamed destructuring
  const { x: vx, y: vy }: Vec2 = v;
  console.log(vx);          // 3
  console.log(vy);          // 4

  // Partial destructuring
  const { x: px }: Vec2 = v;
  console.log(px);          // 3

  // Destructuring from struct param (runtime pointer)
  console.log(sumCoords(v));  // 7

  // Mixed-type struct destructuring
  const p: Particle = { mass: 1.0, charge: -1, active: 1 };
  const { charge, active }: Particle = p;
  console.log(charge);      // -1
  console.log(active);      //  1

  // Renamed from mixed-type struct
  console.log(chargeSign(p));  // -1
}

_start();
