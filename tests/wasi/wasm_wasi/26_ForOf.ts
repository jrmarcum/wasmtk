/**
 * Phase 26: for...of loops; array destructuring with default values
 *
 * Covered:
 *   - for...of over i32[] static array (module-level)
 *   - for...of over i32[] dynamic array (module-level)
 *   - for...of over f64[] array (module-level)
 *   - for...of inside a function over a local array
 *   - for...of with break
 *   - for...of with continue
 *   - Array destructuring with default values: const [a = 10, b = 20] = arr
 */

type i32 = number;
type f64 = number;

// ── for...of over static i32 array ───────────────────────────────────────────

const nums: i32[] = [10, 20, 30];
let total: i32 = 0;
for (const n of nums) {
  total = total + n;
}
console.log(total); // 60

// ── for...of over dynamic i32 array ──────────────────────────────────────────

let dynTotal: i32 = 0;
const dynNums: i32[] = [1, 2, 3, 4, 5];
dynNums.push(6);
for (const x of dynNums) {
  dynTotal = dynTotal + x;
}
console.log(dynTotal); // 21

// ── for...of printing each element ───────────────────────────────────────────

const labels: i32[] = [100, 200, 300];
for (const v of labels) {
  console.log(v);
}
// 100
// 200
// 300

// ── for...of over f64 array ───────────────────────────────────────────────────

const floats: f64[] = [1.5, 2.5, 3.5];
let fsum: f64 = 0.0;
for (const fv of floats) {
  fsum = fsum + fv;
}
console.log(fsum); // 7.5

// ── for...of with break ───────────────────────────────────────────────────────

const data: i32[] = [1, 2, 3, 4, 5];
let found: i32 = -1;
for (const d of data) {
  if (d === 3) {
    found = d;
    break;
  }
}
console.log(found); // 3

// ── for...of with continue ────────────────────────────────────────────────────

const evens: i32[] = [1, 2, 3, 4, 5, 6];
let evenSum: i32 = 0;
for (const e of evens) {
  if (e % 2 !== 0) { continue; }
  evenSum = evenSum + e;
}
console.log(evenSum); // 12

// ── for...of inside a function (over local dynamic array) ────────────────────

function sumDynamic(): i32 {
  const arr: i32[] = [10, 20, 30, 40];
  arr.push(0);
  arr.pop();
  let s: i32 = 0;
  for (const item of arr) {
    s = s + item;
  }
  return s;
}

console.log(sumDynamic()); // 100

// ── Array destructuring with default values ───────────────────────────────────

const dynShort: i32[] = [7];
dynShort.push(0);
dynShort.pop();
const [da = 10, db = 20] = dynShort;
console.log(da); // 7
console.log(db); // 20

// ── Array destructuring defaults with full array ──────────────────────────────

const dynFull: i32[] = [11, 22, 33];
dynFull.push(0);
dynFull.pop();
const [fa = 99, fb = 99, fc = 99] = dynFull;
console.log(fa); // 11
console.log(fb); // 22
console.log(fc); // 33
