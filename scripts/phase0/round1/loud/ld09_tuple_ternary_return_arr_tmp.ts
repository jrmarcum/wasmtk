type i32 = number;
type f64 = number;
function mm(a: i32, b: i32): [i32, i32] { return a < b ? [a, b] : [b, a]; }
const r: [i32, i32] = mm(8, 3);
console.log(r[0], r[1]);
