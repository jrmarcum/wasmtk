// Phase 51.3 — Destructuring in function parameters
// f({ x, y }: Vec2) desugars to a struct-pointer param + `const { x, y } = __pd` binding.
type i32 = number;
type f64 = number;

interface Vec2 {
  x: f64;
  y: f64;
}

interface Counter {
  a: i32;
  b: i32;
}

// Object-destructured param.
function sum2({ x, y }: Vec2): f64 {
  return x + y;
}
console.log("sum2:", sum2({ x: 3.5, y: 4.0 })); // 7.5

// Renamed bindings in the param pattern.
function diff({ a: lo, b: hi }: Counter): i32 {
  return hi - lo;
}
console.log("diff:", diff({ a: 4, b: 10 })); // 6

// Destructured param alongside a normal param.
function scaleX({ x, y }: Vec2, factor: f64): f64 {
  return x * factor + y;
}
console.log("scaleX:", scaleX({ x: 2.0, y: 1.0 }, 3.0)); // 7

// Destructured param used with a struct variable argument.
const v: Vec2 = { x: 10.0, y: 20.0 };
console.log("fromVar:", sum2(v)); // 30

// Tuple-destructured param (called with a tuple variable; inline tuple-literal args are a
// separate, pre-existing gap, so we pass a variable here).
function addPair([p, q]: [i32, i32]): i32 {
  return p + q;
}
const pair: [i32, i32] = [8, 9];
console.log("addPair:", addPair(pair)); // 17

// Two destructured params.
function combine({ x, y }: Vec2, { a, b }: Counter): f64 {
  return x + y + a + b;
}
console.log("combine:", combine({ x: 1.5, y: 2.5 }, { a: 3, b: 4 })); // 11
