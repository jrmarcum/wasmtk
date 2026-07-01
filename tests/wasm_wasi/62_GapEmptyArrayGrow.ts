// deno-fmt-ignore-file
// Compiler-gap regression (2026-06-30): Gap 5.3 — an empty `[]` reconstructed each loop iteration and
// pushed must grow from capacity 0 (grow uses max(cap*2, 8)); the rows must not alias.
type i32 = number;
const grid: i32[][] = [];
for (let i = 0; i < 3; i++) {
  const row: i32[] = [];
  row.push(i);
  row.push(i * 10);
  grid.push(row);
}
const a: i32 = grid[0][0];
const b: i32 = grid[1][1];
const c: i32 = grid[2][0];
console.log(a); // 0
console.log(b); // 10
console.log(c); // 2
console.log(grid.length); // 3
