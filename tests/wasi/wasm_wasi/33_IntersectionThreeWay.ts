// Phase 33 — Intersection types: three-way A & B & C merge
type i32 = number;
type f64 = number;

interface HasA { a: i32; }
interface HasB { b: i32; }
interface HasC { c: f64; }
type ABC = HasA & HasB & HasC;

function sumABC(v: ABC): f64 {
  return (v.a as f64) + (v.b as f64) + v.c;
}

const abc: ABC = { a: 1, b: 2, c: 3.14 };
console.log(abc.a);       // 1
console.log(abc.b);       // 2
console.log(abc.c);       // 3.14
console.log(sumABC(abc)); // 6.14
