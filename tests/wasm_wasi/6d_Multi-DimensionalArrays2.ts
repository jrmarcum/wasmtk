type i32 = number;

export function testMatrix(): i32 {
  const matrix: i32[][] = [[1, 2], [3, 4]];
  // Accessing a nested pointer
  return matrix[1][0]; // Expected: 3
}
console.log(testMatrix()); // Should output 3