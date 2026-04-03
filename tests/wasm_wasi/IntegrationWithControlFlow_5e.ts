type i32 = number;
export function testArrowInLoop(limit: i32): i32 {
  const checker = (n: i32): boolean => n % 2 === 0;
  let count = 0;

  for (let i = 0; i < limit; i++) {
    if (checker(i)) {
      count++;
    }
  }
  return count;
}

console.log(testArrowInLoop(10)); // Output: 5
