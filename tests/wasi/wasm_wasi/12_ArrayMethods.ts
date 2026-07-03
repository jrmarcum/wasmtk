// Phase 12 — Array Methods
// Tests: indexOf, includes, slice, forEach, map, filter, find, reduce
type i32 = number;
type f64 = number;
type bool = boolean;

// ── Setup ────────────────────────────────────────────────────────────────────
const nums: i32[] = [10, 20, 30, 40, 50];

// ── indexOf ───────────────────────────────────────────────────────────────────
const idx: i32 = nums.indexOf(30);
console.log(idx);          // 2

const miss: i32 = nums.indexOf(99);
console.log(miss);         // -1

// ── includes ──────────────────────────────────────────────────────────────────
const has40: bool = nums.includes(40);
console.log(has40);        // true

const has99: bool = nums.includes(99);
console.log(has99);        // false

// ── slice ─────────────────────────────────────────────────────────────────────
const sliced: i32[] = nums.slice(1, 4);   // [20, 30, 40]
console.log(sliced.length);               // 3
console.log(sliced[0]);                   // 20
console.log(sliced[2]);                   // 40

// slice past end — clamps
const tail: i32[] = nums.slice(3, 99);    // [40, 50]
console.log(tail.length);                 // 2
console.log(tail[1]);                     // 50

// ── forEach ───────────────────────────────────────────────────────────────────
function printElem(v: i32): void {
  console.log(v);
}

nums.forEach(printElem);   // 10 20 30 40 50

// ── map ───────────────────────────────────────────────────────────────────────
function doubleIt(v: i32): i32 {
  return v * 2;
}

const doubled: i32[] = nums.map(doubleIt);
console.log(doubled.length);   // 5
console.log(doubled[0]);       // 20
console.log(doubled[4]);       // 100

// ── filter ────────────────────────────────────────────────────────────────────
function isOver25(v: i32): bool {
  return v > 25;
}

const big: i32[] = nums.filter(isOver25);
console.log(big.length);   // 3  (30, 40, 50)
console.log(big[0]);       // 30
console.log(big[2]);       // 50

// ── find ──────────────────────────────────────────────────────────────────────
function isOver15(v: i32): bool {
  return v > 15;
}

const found: i32 | undefined = nums.find(isOver15);
console.log(found);        // 20 (first element > 15)

function isNeg(v: i32): bool {
  return v < 0;
}

const notFound: i32 | undefined = nums.find(isNeg);
console.log(notFound);     // undefined

// ── reduce ────────────────────────────────────────────────────────────────────
function addUp(acc: i32, v: i32): i32 {
  return acc + v;
}

const total: i32 = nums.reduce(addUp, 0);
console.log(total);        // 150  (10+20+30+40+50)

// ── f64 array methods ─────────────────────────────────────────────────────────
const fvals: f64[] = [1.5, 2.5, 3.5];

function dbl(v: f64): f64 {
  return v * 2.0;
}

const fmapped: f64[] = fvals.map(dbl);
console.log(fmapped.length);   // 3
console.log(fmapped[1]);       // 5

function sumF(acc: f64, v: f64): f64 {
  return acc + v;
}

const fsum: f64 = fvals.reduce(sumF, 0.0);
console.log(fsum);             // 7.5
