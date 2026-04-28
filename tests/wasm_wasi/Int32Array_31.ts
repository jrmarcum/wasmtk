// Phase 31 — Int32Array basic tests
type i32 = number;

// ── Creation with literal length ────────────────────────────────────────────
const a: Int32Array = new Int32Array(5);
console.log(a.length);        // 5

// ── Element write and read ───────────────────────────────────────────────────
a[0] = 10;
a[1] = 20;
a[2] = 30;
a[3] = 40;
a[4] = 50;
console.log(a[0]);            // 10
console.log(a[1]);            // 20
console.log(a[4]);            // 50

// ── .length after writes ─────────────────────────────────────────────────────
console.log(a.length);        // 5

// ── .byteLength ─────────────────────────────────────────────────────────────
console.log(a.byteLength);    // 20

// ── console.log(arr) — prints TypedArray header and contents ─────────────────
console.log(a);               // Int32Array(5) [ 10, 20, 30, 40, 50 ]

// ── Creation from literal array ─────────────────────────────────────────────
const b: Int32Array = new Int32Array([1, 2, 3]);
console.log(b.length);        // 3
console.log(b[0]);            // 1
console.log(b[2]);            // 3
console.log(b);               // Int32Array(3) [ 1, 2, 3 ]

// ── .fill(val) — fill entire array ──────────────────────────────────────────
const c: Int32Array = new Int32Array(4);
c.fill(7);
console.log(c[0]);            // 7
console.log(c[3]);            // 7
console.log(c);               // Int32Array(4) [ 7, 7, 7, 7 ]

// ── .fill(val, start) — fill from index ─────────────────────────────────────
const d: Int32Array = new Int32Array([1, 2, 3, 4, 5]);
d.fill(9, 2);
console.log(d[0]);            // 1
console.log(d[2]);            // 9
console.log(d[4]);            // 9

// ── .fill(val, start, end) — fill range ──────────────────────────────────────
const e: Int32Array = new Int32Array([1, 2, 3, 4, 5]);
e.fill(0, 1, 3);
console.log(e[0]);            // 1
console.log(e[1]);            // 0
console.log(e[2]);            // 0
console.log(e[3]);            // 4
