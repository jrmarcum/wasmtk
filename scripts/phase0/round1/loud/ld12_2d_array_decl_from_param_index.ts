type i32 = number;
type f64 = number;
function t(rows: i32[][]): i32 { const d: i32[][] = rows; return d[1][2]; }
console.log(t([[1, 2], [3, 4, 5]]));
