// Phase 31 — Combined test: Int32Array, Float64Array, Uint8Array together
type i32 = number;
type f64 = number;

// ── Int32Array — all features ─────────────────────────────────────────────────
const ints: Int32Array = new Int32Array([5, 10, 15, 20]);
console.log(ints.length);     // 4
console.log(ints.byteLength); // 16
console.log(ints[0]);         // 5
console.log(ints[3]);         // 20
ints[1] = 99;
console.log(ints[1]);         // 99
console.log(ints);            // Int32Array(4) [ 5, 99, 15, 20 ]

// ── Float64Array — all features ───────────────────────────────────────────────
const floats: Float64Array = new Float64Array([1.1, 2.2, 3.3]);
console.log(floats.length);   // 3
console.log(floats.byteLength); // 24
console.log(floats[0]);       // 1.1
floats[2] = 9.9;
console.log(floats[2]);       // 9.9
console.log(floats);          // Float64Array(3) [ 1.1, 2.2, 9.9 ]

// ── fill on Int32Array ────────────────────────────────────────────────────────
const fi: Int32Array = new Int32Array(3);
fi.fill(42);
console.log(fi[0]);           // 42
console.log(fi[2]);           // 42

// ── fill on Float64Array ──────────────────────────────────────────────────────
const ff: Float64Array = new Float64Array(3);
ff.fill(1.5);
console.log(ff[0]);           // 1.5
console.log(ff[2]);           // 1.5

// ── Uint8Array ────────────────────────────────────────────────────────────────
const bytes: Uint8Array = new Uint8Array([0, 127, 255]);
console.log(bytes[0]);        // 0
console.log(bytes[1]);        // 127
console.log(bytes[2]);        // 255
console.log(bytes.length);    // 3
console.log(bytes.byteLength); // 3

// ── Interaction: Int32Array element used in arithmetic ────────────────────────
const nums: Int32Array = new Int32Array([3, 7, 2]);
const total: i32 = nums[0] + nums[1] + nums[2];
console.log(total);           // 12
