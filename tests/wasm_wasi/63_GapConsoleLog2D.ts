// deno-fmt-ignore-file
// Regression (2026-06-30): a 2D dynamic-array element `grid[i][j]` directly in console.log (and as an
// operand) was emitting a comment-stub → 0. Now loads the row pointer then the element.
type i32 = number;
type f64 = number;
const grid: i32[][] = [[1, 2, 3], [4, 5, 6]];
const fg: f64[][] = [[1.5, 2.5], [3.5, 4.5]];
console.log(grid[0][0]); // 1
console.log(grid[1][2]); // 6
console.log(fg[1][0]); // 3.5
console.log("sum:", grid[0][0] + grid[0][1]); // sum: 3
