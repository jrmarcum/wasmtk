// Phase 33 regression guards (2026-07-30) — the shapes the base-prefix check must NOT reject.
// Companion to 33_IntersectionBasePrefixGuard (which pins the rejected shape). If a future
// "simplification" widens the guard, these four calls start failing to compile.
type i32 = number;
type f64 = number;

interface Base {
  bx: i32;
  by: i32;
}

interface Extra {
  ez: f64;
}

interface More {
  mw: i32;
}

// Base FIRST — Base is a byte-exact prefix of both
type WithExtra = Base & Extra;
type WithAll = Base & Extra & More;

// Guard 1: base-typed parameter, two-way intersection argument
function sumBase(b: Base): i32 {
  return b.bx + b.by;
}

// Guard 2: base-typed parameter, three-way intersection argument (deeper chain, same prefix)
// Guard 3: the intermediate intersection is itself a prefix of the longer chain
function scaleExtra(w: WithExtra): f64 {
  return w.ez * 2.0;
}

// Guard 4: exact-type parameter — no widening involved at all
function allFields(a: WithAll): i32 {
  return a.bx + a.by + a.mw;
}

const two: WithExtra = { bx: 3, by: 4, ez: 1.5 };
const three: WithAll = { bx: 10, by: 20, ez: 2.5, mw: 7 };

console.log("sumBase(two):", sumBase(two)); // 7
console.log("sumBase(three):", sumBase(three)); // 30
console.log("scaleExtra(two):", scaleExtra(two)); // 3
console.log("scaleExtra(three):", scaleExtra(three)); // 5
console.log("allFields(three):", allFields(three)); // 37
