// Phase 52.6 — chained assignment `a = b = c = 0`: the rightmost value propagates leftward.
type i32 = number;
type f64 = number;

let a: i32 = 0;
let b: i32 = 0;
let c: i32 = 0;
a = b = c = 7;
console.log("a:", a); // 7
console.log("b:", b); // 7
console.log("c:", c); // 7

let x: f64 = 1.0;
let y: f64 = 2.0;
x = y = 9.5;
console.log("x:", x); // 9.5
console.log("y:", y); // 9.5

function f(): i32 {
  let p: i32 = 0;
  let q: i32 = 0;
  let r: i32 = 0;
  p = q = r = 4;
  return p + q + r; // 12
}
console.log("f:", f()); // 12
