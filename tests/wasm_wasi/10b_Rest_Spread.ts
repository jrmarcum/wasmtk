type i32 = number;

export function testArrayRest(): i32 {
  const nums: i32[] = [10, 20, 30];
  
  // Destructuring using the 'rest' pattern
  const [_first, ...rest] = nums; 
  
  // Verification: The 'rest' array should be a new dynamic array
  return rest.length; // Expected: 2
}

console.log(testArrayRest()); // Should output: 2