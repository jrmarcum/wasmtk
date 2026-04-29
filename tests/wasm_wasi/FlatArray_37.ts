// Phase 37 — flat()
// Tests: flat() on i32[][] flattens one level into i32[]
type i32 = number;

// Basic 3-row flatten
const matrix: i32[][] = [[1, 2, 3], [4, 5], [6]];
const flat: i32[] = matrix.flat();

console.log(flat[0]);  // 1
console.log(flat[1]);  // 2
console.log(flat[2]);  // 3
console.log(flat[3]);  // 4
console.log(flat[4]);  // 5
console.log(flat[5]);  // 6

// Single-row matrix
const single: i32[][] = [[10, 20, 30]];
const fs: i32[] = single.flat();
console.log(fs[0]);  // 10
console.log(fs[2]);  // 30

// Rows of length 1
const ones: i32[][] = [[7], [8], [9]];
const fo: i32[] = ones.flat();
console.log(fo[0]);  // 7
console.log(fo[1]);  // 8
console.log(fo[2]);  // 9

// Dynamic rows (push into 2D array)
const dyn: i32[][] = [[100, 200], [300]];
dyn[0].push(250);
const fd: i32[] = dyn.flat();
console.log(fd[0]);  // 100
console.log(fd[1]);  // 200
console.log(fd[2]);  // 250
console.log(fd[3]);  // 300
