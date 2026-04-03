type i32 = number;
type f64 = number;

function sumArray(arr: i32[], len: i32): i32 {
  let total: i32 = 0;
  let i: i32 = 0;
  while (i < len) {
    total = total + arr[i];
    i = i + 1;
  }
  return total;
}

export function _start(): void {
  const nums: i32[] = [10, 20, 30, 40, 50];
  console.log(nums.length);      // 5
  console.log(nums[0]);          // 10
  console.log(nums[4]);          // 50

  nums[2] = 99;
  console.log(nums[2]);          // 99

  console.log(sumArray(nums, nums.length)); // 10+20+99+40+50 = 219

  const vals: f64[] = [1.5, 2.5, 3.0];
  console.log(vals.length);      // 3
  console.log(vals[1]);          // 2.5
}

_start();
