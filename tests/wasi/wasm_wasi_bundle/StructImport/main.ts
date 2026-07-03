import { Vec2, dot, lengthSq } from "./vec.ts";

type f64 = number;

function main(): void {
  const a: Vec2 = { x: 3.0, y: 4.0 };
  const b: Vec2 = { x: 1.0, y: 2.0 };
  console.log(lengthSq(a));  // 25
  console.log(dot(a, b));    // 11
}

main();
