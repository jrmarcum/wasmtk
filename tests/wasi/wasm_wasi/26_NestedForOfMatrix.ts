type i32 = number;

export function testNestedForOf(): void {
  console.log("--- Test 3: Nested for...of Matrix Iteration ---");

  const matrix: i32[][] = [
    [1, 2],
    [3, 4],
    [5, 6],
  ];

  let total: i32 = 0;

  for (const row of matrix) {
    for (const val of row) {
      total += val;
    }
  }

  console.log("Matrix Total Sum:", total); // Expected: 1+2+3+4+5+6 = 21
}

testNestedForOf();
