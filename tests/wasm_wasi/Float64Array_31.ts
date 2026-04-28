// Phase 31 — Float64Array basic tests
type f64 = number;

// ── Creation with literal length ────────────────────────────────────────────
const a: Float64Array = new Float64Array(3);
console.log(a.length);        // 3

// ── Element write and read ───────────────────────────────────────────────────
a[0] = 1.5;
a[1] = 2.5;
a[2] = 3.5;
console.log(a[0]);            // 1.5
console.log(a[1]);            // 2.5
console.log(a[2]);            // 3.5

// ── .byteLength ─────────────────────────────────────────────────────────────
console.log(a.byteLength);    // 24

// ── console.log(arr) — prints TypedArray header and contents ─────────────────
console.log(a);               // Float64Array(3) [ 1.5, 2.5, 3.5 ]

// ── Creation from literal array ──────────────────────────────────────────────
const b: Float64Array = new Float64Array([0.1, 0.2, 0.3]);
console.log(b.length);        // 3
console.log(b[0]);            // 0.1
console.log(b[2]);            // 0.3
console.log(b);               // Float64Array(3) [ 0.1, 0.2, 0.3 ]

// ── .fill(val) ───────────────────────────────────────────────────────────────
const c: Float64Array = new Float64Array(4);
c.fill(3.14);
console.log(c[0]);            // 3.14
console.log(c[3]);            // 3.14

// ── .fill(val, start, end) ───────────────────────────────────────────────────
const d: Float64Array = new Float64Array([1.0, 2.0, 3.0, 4.0]);
d.fill(0.0, 1, 3);
console.log(d[0]);            // 1
console.log(d[1]);            // 0
console.log(d[2]);            // 0
console.log(d[3]);            // 4
