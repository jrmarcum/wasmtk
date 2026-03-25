type i32 = number;
type f64 = number;

export interface Vec2 {
  x: f64;
  y: f64;
}

export function dot(a: Vec2, b: Vec2): f64 {
  return a.x * b.x + a.y * b.y;
}

export function lengthSq(v: Vec2): f64 {
  return v.x * v.x + v.y * v.y;
}
