// H12 sw34 (2026-09-29): `x instanceof Y` inside a console expression (a ternary condition) was
// stubbed to 0, so `e instanceof Error ? "is error" : "not error"` printed `not error` for a caught
// Error. The console path now asks wasic for every `instanceof`, the Error family included.
type i32 = number;

class Shape {
  size: i32;
  constructor(size: i32) {
    this.size = size;
  }
}
class Box extends Shape {
  constructor(size: i32) {
    super(size);
  }
}

function risky(k: i32): i32 {
  if (k > 0) throw new TypeError("boom");
  return k;
}

try {
  risky(1);
} catch (e) {
  console.log(e instanceof Error ? "is error" : "not error");
  console.log(e instanceof Error);
  console.log("msg:", e instanceof Error ? e.message : "?");
}

const b: Box = new Box(3);
const s: Shape = new Shape(2);
console.log(b instanceof Box ? "box" : "not box");
console.log(s instanceof Box ? "box" : "not box");
console.log(b instanceof Shape);
