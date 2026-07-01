// deno-fmt-ignore-file
// Regression (2026-06-30): a `const NAME: T[] = []` nested in a SINGLE-PHYSICAL-line loop body must be
// registered (was `'row' is not defined`). Emission already handles single-line bodies via splitStmts.
type i32 = number;
const grid: i32[][] = [];
for (let i = 0; i < 3; i++) { const row: i32[] = []; row.push(i); row.push(i * 10); grid.push(row); }
const a: i32 = grid[0][0];
const b: i32 = grid[1][1];
console.log(a); // 0
console.log(b); // 10
console.log(grid.length); // 3
