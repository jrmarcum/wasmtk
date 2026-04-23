// Phase 28 — Extended Array Methods
// Tests: every, some, findIndex, at, reverse, fill, join, sort
type i32 = number;
type bool = boolean;

// ── Setup ─────────────────────────────────────────────────────────────────────
const nums: i32[] = [10, 20, 30, 40, 50];

// ── every ─────────────────────────────────────────────────────────────────────
function isPositive(v: i32): bool { return v > 0; }
function isOver10(v: i32): bool { return v > 10; }

console.log(nums.every(isPositive));   // true
console.log(nums.every(isOver10));     // false

// ── some ──────────────────────────────────────────────────────────────────────
function isOver25(v: i32): bool { return v > 25; }
function isNeg(v: i32): bool { return v < 0; }

console.log(nums.some(isOver25));   // true
console.log(nums.some(isNeg));      // false

// ── findIndex ─────────────────────────────────────────────────────────────────
function isOver15(v: i32): bool { return v > 15; }

const fi: i32 = nums.findIndex(isOver15);
console.log(fi);    // 1

function isBig(v: i32): bool { return v > 100; }
const fi2: i32 = nums.findIndex(isBig);
console.log(fi2);   // -1

// ── at ────────────────────────────────────────────────────────────────────────
console.log(nums.at(0));    // 10
console.log(nums.at(2));    // 30
console.log(nums.at(-1));   // 50
console.log(nums.at(-2));   // 40

// ── reverse ───────────────────────────────────────────────────────────────────
const rev: i32[] = [1, 2, 3, 4, 5];
rev.reverse();
console.log(rev[0]);   // 5
console.log(rev[4]);   // 1
console.log(rev[2]);   // 3

// ── fill ──────────────────────────────────────────────────────────────────────
const fill1: i32[] = [1, 2, 3, 4, 5];
fill1.fill(0);
console.log(fill1[0]);   // 0
console.log(fill1[4]);   // 0

const fill2: i32[] = [1, 2, 3, 4, 5];
fill2.fill(9, 2);
console.log(fill2[0]);   // 1
console.log(fill2[2]);   // 9
console.log(fill2[4]);   // 9

const fill3: i32[] = [1, 2, 3, 4, 5];
fill3.fill(7, 1, 3);
console.log(fill3[0]);   // 1
console.log(fill3[1]);   // 7
console.log(fill3[2]);   // 7
console.log(fill3[3]);   // 4

// ── join ──────────────────────────────────────────────────────────────────────
const ja: i32[] = [1, 2, 3];
console.log(ja.join(","));    // 1,2,3
console.log(ja.join(" - ")); // 1 - 2 - 3

// ── sort (natural ascending) ──────────────────────────────────────────────────
const unsorted: i32[] = [3, 1, 4, 1, 5, 9, 2, 6];
unsorted.sort();
console.log(unsorted[0]);   // 1
console.log(unsorted[1]);   // 1
console.log(unsorted[7]);   // 9

// ── sort with comparator (descending) ────────────────────────────────────────
function cmpDesc(a: i32, b: i32): i32 { return b - a; }
const desc: i32[] = [3, 1, 4, 1, 5];
desc.sort(cmpDesc);
console.log(desc[0]);   // 5
console.log(desc[4]);   // 1
