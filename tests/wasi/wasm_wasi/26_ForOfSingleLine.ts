// Regression: brace-less single-line `for...of` body must not be dropped (was silently skipped).
type i32 = number;
const nums: i32[] = [10, 20, 30];
let total: i32 = 0;
for (const n of nums) total = total + n;
console.log(total); // 60

let count: i32 = 0;
const dyn: i32[] = [1, 2, 3, 4];
dyn.push(5);
for (const x of dyn) count = count + 1;
console.log(count); // 5
