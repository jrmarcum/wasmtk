// Phase 52.7 — `"field" in obj`: closed-world compile-time membership test (struct/class fields).
type i32 = number;

interface Point {
  x: i32;
  y: i32;
}

class Box {
  w: i32;
  h: i32;
  constructor(w: i32, h: i32) {
    this.w = w;
    this.h = h;
  }
}

const pt: Point = { x: 1, y: 2 };
const hasX: boolean = "x" in pt;
const hasZ: boolean = "z" in pt;
console.log("hasX:", hasX); // true
console.log("hasZ:", hasZ); // false

if ("y" in pt) {
  console.log("y present"); // printed
}
if ("q" in pt) {
  console.log("q present");
} else {
  console.log("q absent"); // printed
}

const b: Box = new Box(3, 4);
const hasW: boolean = "w" in b;
const hasArea: boolean = "area" in b;
console.log("hasW:", hasW); // true
console.log("hasArea:", hasArea); // false
