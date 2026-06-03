type i32 = number;
export function testClosure(multiplier: i32): i32 {
  // 'multiplier' is captured from the outer scope
  const scale = (val: i32): i32 => val * multiplier;

  return scale(10);
}

console.log(testClosure(5)); // Output: 50