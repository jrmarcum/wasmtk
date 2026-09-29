type i32 = number; type f64 = number;
const n: i32 = 8; const h: i32 = n >> 1; const m: i32 = n > 3 ? n : 3;
const s: string = "h=" + (n >> 1);
console.log(h); console.log(m); console.log(s);
