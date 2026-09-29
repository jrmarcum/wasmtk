type i32 = number;
type f64 = number;
function mk(): i32[][] { const m: i32[][] = [[1], [2, 3]]; return m; }
const d: i32[][] = mk();
console.log(d[1][1]);
