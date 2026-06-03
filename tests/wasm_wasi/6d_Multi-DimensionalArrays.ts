type i32 = number;
const matrix: i32[][] = [[1, 2], [3, 4]];
matrix[0].push(5);
console.log(matrix); // Output: [[1, 2, 5], [3, 4]]