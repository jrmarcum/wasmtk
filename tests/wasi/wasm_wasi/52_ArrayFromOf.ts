// Phase 52.8 — Array.from([…]) / Array.of(…) (array-literal sugar) + Array.isArray (closed-world).
type i32 = number;
type f64 = number;

const a: i32[] = Array.from([1, 2, 3]);
console.log("a.length:", a.length); // 3
console.log("a[0]:", a[0]); // 1
console.log("a[2]:", a[2]); // 3

const b: i32[] = Array.of(10, 20, 30, 40);
console.log("b.length:", b.length); // 4
console.log("b[1]:", b[1]); // 20

const c: f64[] = Array.of(1.5, 2.5);
console.log("c sum:", c[0] + c[1]); // 4

const e: i32[] = Array.of();
console.log("e.length:", e.length); // 0

const isArr: boolean = Array.isArray(a);
const isArr2: boolean = Array.isArray(b);
const notArr: boolean = Array.isArray(isArr);
console.log("isArr:", isArr); // true
console.log("isArr2:", isArr2); // true
console.log("notArr:", notArr); // false
