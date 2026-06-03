// Phase_10b_DynamicOps.ts
type i32 = number;

export function testDynamicOps(): i32 {
  const nums: i32[] = [10, 20];
  
  // 1. Test Push (Triggering potential resize)
  nums.push(30);
  
  // 2. Test Shift (Triggering memory.copy move)
  const _first = nums.shift(); // first = 10, nums = [20, 30]
  
  // 3. Test Length update
  return nums.length; // Expected: 2
}

console.log(testDynamicOps()); // Should output: 2