// Phase 13 — Rest Parameters & Spread
// Tests: rest params, spread array literal, spread call

// ── Rest parameters ───────────────────────────────────────────────────────────

function sumAll(...nums: i32[]): i32 {
  let total: i32 = 0;
  let i: i32 = 0;
  const len: i32 = nums.length;
  while (i < len) {
    total = total + nums[i];
    i = i + 1;
  }
  return total;
}

// Call with inline literal args — builds temp heap array
const s1: i32 = sumAll(1, 2, 3);
console.log(s1);          // 6

const s2: i32 = sumAll(10, 20, 30, 40);
console.log(s2);          // 100

// ── Rest param with normal leading args ───────────────────────────────────────

function prefixedSum(prefix: i32, ...nums: i32[]): i32 {
  let total: i32 = prefix;
  let i: i32 = 0;
  const len: i32 = nums.length;
  while (i < len) {
    total = total + nums[i];
    i = i + 1;
  }
  return total;
}

const ps: i32 = prefixedSum(100, 1, 2, 3);
console.log(ps);          // 106

// ── Spread call: foo(...arr) ──────────────────────────────────────────────────

const arr1: i32[] = [5, 10, 15];
const s3: i32 = sumAll(...arr1);
console.log(s3);          // 30

// ── Spread array literal: const merged = [...a, ...b] ─────────────────────────

const a: i32[] = [1, 2, 3];
const b: i32[] = [4, 5, 6];
const merged: i32[] = [...a, ...b];
console.log(merged.length);  // 6
console.log(merged[0]);      // 1
console.log(merged[5]);      // 6

// ── Three-way spread ─────────────────────────────────────────────────────────

const c: i32[] = [7, 8];
const abc: i32[] = [...a, ...b, ...c];
console.log(abc.length);  // 8
console.log(abc[6]);      // 7
console.log(abc[7]);      // 8

// ── f64 rest parameters ───────────────────────────────────────────────────────

function avgF(...vals: f64[]): f64 {
  let sum: f64 = 0.0;
  let i: i32 = 0;
  const len: i32 = vals.length;
  while (i < len) {
    sum = sum + vals[i];
    i = i + 1;
  }
  return sum;
}

const fsum: f64 = avgF(1.5, 2.5, 3.0);
console.log(fsum);        // 7
