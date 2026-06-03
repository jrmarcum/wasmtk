type f64 = number;
interface Vec2 {
  x: f64;
  y: f64;
}

export function testDestructuring(): f64 {
  const v: Vec2 = { x: 10.5, y: 20.5 };
  // Mapping 'x' and 'y' to memory loads
  const { x, y } = v;
  return x + y;
}

console.log(testDestructuring()); // Should output 31.0