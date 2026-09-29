type i32 = number;
type f64 = number;
function t(xs: i32[]): i32 { const d: i32[] = xs; let s: i32 = 0; for (let i = 0; i < d.length; i++) s = s + d[i]; return s; }
console.log(t([1, 2, 3]));
