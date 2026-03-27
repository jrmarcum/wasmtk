// Phase 10c — Dynamic Array Growth (realloc via bump allocator)
// Initial capacity = max(initLen*2, 8) = 8 for a 3-element array.
// Push 6 more elements (total 9) to force a grow from cap=8 to cap=16.

const nums: i32[] = [1, 2, 3];
nums.push(4);
nums.push(5);
nums.push(6);
nums.push(7);
nums.push(8);
// capacity was 8, now full — next push triggers grow to cap=16
nums.push(9);
console.log(nums[0]);        // 1
console.log(nums[8]);        // 9
console.log(nums.length);    // 9

// unshift into a full array (cap still 16, len=9, plenty of room first)
// Fill to capacity=16 then unshift to force another grow
nums.push(10);
nums.push(11);
nums.push(12);
nums.push(13);
nums.push(14);
nums.push(15);
nums.push(16);
// now len=16, cap=16 — next unshift triggers grow to cap=32
nums.unshift(0);
console.log(nums[0]);        // 0
console.log(nums[1]);        // 1
console.log(nums.length);    // 17

// pop still works on grown array
const last: i32 = nums.pop();
console.log(last);           // 16
console.log(nums.length);    // 16

// f64 growth test
const scores: f64[] = [1.0, 2.0, 3.0];
scores.push(4.0);
scores.push(5.0);
scores.push(6.0);
scores.push(7.0);
scores.push(8.0);
// cap=8, now full — next push triggers grow
scores.push(9.0);
console.log(scores[0]);      // 1
console.log(scores[8]);      // 9
console.log(scores.length);  // 9
