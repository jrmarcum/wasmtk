// Regression: method calls / `new` on BOTH sides of a binary operator must compile (the greedy
// dotCallExprMatch / newMatch arg regexes used to consume across the operator, so tests had to hoist
// `const av = a.unwrap()` temporaries — see cmem). Now the parenDepthNeverNegative guard makes the
// compound expression fall through to the binary-op loop.

type i32 = number;

class Box {
  v: i32;
  constructor(x: i32) {
    this.v = x;
  }
  unwrap(): i32 {
    return this.v;
  }
}

function sumTwo(a: Box, b: Box): i32 {
  return a.unwrap() + b.unwrap(); // method call on both sides of +
}

function maxTwo(a: Box, b: Box): i32 {
  return a.unwrap() > b.unwrap() ? a.unwrap() : b.unwrap(); // comparison + ternary, all method calls
}

const p: Box = new Box(3);
const q: Box = new Box(4);

console.log(sumTwo(p, q)); // 7
console.log(maxTwo(p, q)); // 4
console.log(p.unwrap() + q.unwrap() + 10); // 17 (three-term, two method calls)
console.log(p.unwrap() === q.unwrap() ? 1 : 0); // 0
// NOTE: chained `new X(...).method()` inside a binary op (`new Box(5).unwrap() + ...`) is a SEPARATE
// still-unhandled gap (the new+method chain has no handler) — out of scope for this regression.
