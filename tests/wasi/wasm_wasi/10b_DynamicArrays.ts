// Phase 10b — Dynamic Array push / pop / shift / unshift
// Tests heap-allocated arrays with a [length, capacity] header.

// --- push ---
type i32 = number;
type f64 = number;
const nums: i32[] = [10, 20, 30];
nums.push(40);
nums.push(50);
console.log(nums[0]);         // 10
console.log(nums[3]);         // 40
console.log(nums[4]);         // 50
console.log(nums.length);     // 5

// --- pop ---
const val1: i32 = nums.pop()!;
console.log(val1);            // 50
console.log(nums.length);     // 4

// --- shift ---
const val2: i32 = nums.shift()!;
console.log(val2);            // 10
console.log(nums[0]);         // 20  (shifted left)
console.log(nums.length);     // 3

// --- unshift ---
nums.unshift(5);
console.log(nums[0]);         // 5
console.log(nums[1]);         // 20
console.log(nums.length);     // 4

// --- element write still works ---
nums[0] = 99;
console.log(nums[0]);         // 99

// --- f64 dynamic array ---
const scores: f64[] = [1.5, 2.5];
scores.push(3.5);
console.log(scores[2]);       // 3.5
console.log(scores.length);   // 3
const last: f64 = scores.pop()!;
console.log(last);            // 3.5
console.log(scores.length);   // 2
