type i32 = number;
function dbl(x: i32): i32 { return x * 2; }
function tri(x: i32): i32 { return x * 3; }
const useTri: boolean = true;
const a: (x: i32) => i32 = dbl;
const op: (x: i32) => i32 = useTri ? tri : dbl;
console.log(op(5));
