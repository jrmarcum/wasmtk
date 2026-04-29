// Phase 37 — flatMap()
// Tests: flatMap(fn) maps each element to an array and flattens one level
type i32 = number;

// fn: i32 → [v, v*2]
function expand(v: i32): i32[] {
  return [v, v * 2];
}

const nums: i32[] = [1, 2, 3];
const result: i32[] = nums.flatMap(expand);

console.log(result[0]);  // 1
console.log(result[1]);  // 2
console.log(result[2]);  // 2
console.log(result[3]);  // 4
console.log(result[4]);  // 3
console.log(result[5]);  // 6

// fn that returns a singleton array
function wrap(v: i32): i32[] {
  return [v + 10];
}

const src: i32[] = [5, 6, 7];
const wrapped: i32[] = src.flatMap(wrap);
console.log(wrapped[0]);  // 15
console.log(wrapped[1]);  // 16
console.log(wrapped[2]);  // 17

// fn that returns a triple
function triple(v: i32): i32[] {
  return [v, v * 2, v * 3];
}

const base: i32[] = [2, 4];
const tripled: i32[] = base.flatMap(triple);
console.log(tripled[0]);  // 2
console.log(tripled[1]);  // 4
console.log(tripled[2]);  // 6
console.log(tripled[3]);  // 4
console.log(tripled[4]);  // 8
console.log(tripled[5]);  // 12
