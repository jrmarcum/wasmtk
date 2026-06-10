// Regression for two audit fixes:
//   #3 chained `new ClassName(...).method(...)` — construct a fresh instance and call a method on it
//      (in assignments, returns, binary ops, AND directly inside console.log).
//   #4 module-level multi-statement single physical line (`const a = 1; const b = 2;`) is split into
//      separate _start statements (and i32 module-global arithmetic in console.log uses i32.add).

type i32 = number;

class Box {
  v: i32;
  constructor(x: i32) {
    this.v = x;
  }
  unwrap(): i32 {
    return this.v;
  }
  dbl(): i32 {
    return this.v * 2;
  }
}

// #4: two statements on one physical line at module scope
const a: i32 = 10;
const b: i32 = 20;
console.log(a + b); // 30 (i32 module-global arithmetic → i32.add, not f64.add)

// #3: chained new().method()
console.log(new Box(5).unwrap()); // 5 (directly in console.log)
console.log(new Box(7).dbl()); // 14
console.log(new Box(5).unwrap() + new Box(6).unwrap()); // 11 (binary op of chains)

const z: i32 = new Box(9).dbl(); // assignment
console.log(z); // 18

function firstOf(x: i32): i32 {
  return new Box(x).unwrap(); // return position
}
console.log(firstOf(42)); // 42
