// deno-fmt-ignore-file
// Regression (2026-06-30): a module-GLOBAL array read/written INSIDE a function must resolve its base
// to (global.get $arr), not the raw (i32.const -2) sentinel (was reading address -2 → 0).
type i32 = number;
const arr: i32[] = [10, 20, 30];
function get1(): i32 { return arr[1]; }
function setAt(i: i32, v: i32): void { arr[i] = v; }
function sum(): i32 { let t: i32 = 0; for (let i = 0; i < arr.length; i++) { t = t + arr[i]; } return t; }
console.log(get1()); // 20
setAt(1, 99);
console.log(arr[1]); // 99
console.log(sum()); // 139
