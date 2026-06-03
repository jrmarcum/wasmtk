type i32 = number;
export function testLoops(n: i32): i32 {
  let total: i32 = 0;

  // Basic for-loop
  for (let i = 0; i < n; i++) {
    total += i;
  }

  // Do-while (ensures body runs at least once)
  let j = 0;
  do {
    total += 1;
    j++;
  } while (j < 5);

  // Nested for-loops
  for (let x = 0; x < 3; x++) {
    for (let y = 0; y < 3; y++) {
      total += 1;
    }
  }

  return total;
}

console.log(testLoops(10));