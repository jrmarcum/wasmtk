type i32 = number;
type f64 = number;
const recs: Array<{ a: i32; b: i32 }> = [];
recs.push({ a: 1, b: 2 });
const t: { a: i32; b: i32 } = recs[0];
console.log(t.a + t.b);
