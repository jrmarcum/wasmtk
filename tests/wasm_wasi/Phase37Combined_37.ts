// Phase 37 — flat() + flatMap() combined
type i32 = number;

// ── flat() ────────────────────────────────────────────────────────────────────
const nested: i32[][] = [[10, 20], [30, 40], [50]];
const flattened: i32[] = nested.flat();
console.log(flattened[0]);  // 10
console.log(flattened[1]);  // 20
console.log(flattened[2]);  // 30
console.log(flattened[3]);  // 40
console.log(flattened[4]);  // 50

// flat() then access with slice to verify dynamic layout
const parts: i32[][] = [[1, 2, 3], [4, 5, 6]];
const joined: i32[] = parts.flat();
const sub: i32[] = joined.slice(2, 5);
console.log(sub[0]);  // 3
console.log(sub[1]);  // 4
console.log(sub[2]);  // 5

// ── flatMap() ─────────────────────────────────────────────────────────────────
function double(v: i32): i32[] {
  return [v, v + 10];
}

const vals: i32[] = [1, 2, 3];
const mapped: i32[] = vals.flatMap(double);
console.log(mapped[0]);  // 1
console.log(mapped[1]);  // 11
console.log(mapped[2]);  // 2
console.log(mapped[3]);  // 12
console.log(mapped[4]);  // 3
console.log(mapped[5]);  // 13

// flatMap result can be further transformed
function addOne(v: i32): i32 { return v + 1; }
const bumped: i32[] = mapped.map(addOne);
console.log(bumped[0]);  // 2
console.log(bumped[5]);  // 14
