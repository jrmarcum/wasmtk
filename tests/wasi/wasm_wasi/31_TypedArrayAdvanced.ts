// Phase 31 — Advanced TypedArray tests: runtime length, Uint8Array, .set(), function params
type i32 = number;
type f64 = number;

// ── Runtime length ───────────────────────────────────────────────────────────
const n: i32 = 4;
const rt: Int32Array = new Int32Array(n);
console.log(rt.length);       // 4
rt[0] = 100;
rt[3] = 200;
console.log(rt[0]);           // 100
console.log(rt[3]);           // 200

// ── Uint8Array ────────────────────────────────────────────────────────────────
const u8: Uint8Array = new Uint8Array(3);
u8[0] = 255;
u8[1] = 128;
u8[2] = 0;
console.log(u8[0]);           // 255
console.log(u8[1]);           // 128
console.log(u8[2]);           // 0
console.log(u8.length);       // 3
console.log(u8.byteLength);   // 3

// ── Uint8Array from literal array ────────────────────────────────────────────
const u8b: Uint8Array = new Uint8Array([10, 20, 30]);
console.log(u8b[0]);          // 10
console.log(u8b[1]);          // 20
console.log(u8b[2]);          // 30

// ── .set() — copy from another TypedArray ─────────────────────────────────────
const dst: Int32Array = new Int32Array(5);
const src: Int32Array = new Int32Array([1, 2, 3]);
dst.set(src);
console.log(dst[0]);          // 1
console.log(dst[1]);          // 2
console.log(dst[2]);          // 3
console.log(dst[3]);          // 0

// ── .set() with offset ────────────────────────────────────────────────────────
const dst2: Int32Array = new Int32Array(5);
const src2: Int32Array = new Int32Array([7, 8, 9]);
dst2.set(src2, 2);
console.log(dst2[0]);         // 0
console.log(dst2[2]);         // 7
console.log(dst2[3]);         // 8
console.log(dst2[4]);         // 9

// ── Function accepting Int32Array param ──────────────────────────────────────
function sumArray(arr: Int32Array): i32 {
  let total: i32 = 0;
  let i: i32 = 0;
  const len: i32 = arr.length;
  for (let j: i32 = 0; j < len; j = j + 1) {
    total = total + arr[j];
  }
  return total;
}

const vals: Int32Array = new Int32Array([1, 2, 3, 4, 5]);
console.log(sumArray(vals));  // 15
