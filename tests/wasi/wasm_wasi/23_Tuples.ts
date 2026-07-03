/**
 * Phase 23: Tuple types [A, B, C]
 *
 * Tuples are anonymous fixed-layout structs with positional fields _0, _1, …
 * They reuse the existing struct infrastructure (malloc, field load/store).
 *
 * Covered:
 *   - Named tuple type aliases:   type Pair = [i32, i32]
 *   - Inline tuple declarations:  const t: [i32, f64] = [1, 2.0]
 *   - Positional element access:  t[0], t[1]
 *   - Positional element write:   t[0] = 5
 *   - Tuple destructuring:        const [a, b] = t
 *   - Tuple return types:         function minMax(): [i32, i32]
 *   - return [e0, e1] literal
 *   - Tuple-typed parameters:     function swap(t: [i32, i32]): [i32, i32]
 */

type i32 = number;
type f64 = number;

// ── Named tuple alias ────────────────────────────────────────────────────────

type Pair = [i32, i32];

// ── Constant tuple literal ───────────────────────────────────────────────────

const origin: [i32, i32] = [0, 0];
console.log(origin[0]); // 0
console.log(origin[1]); // 0

// ── Initialised tuple literal ────────────────────────────────────────────────

const pt: [i32, f64] = [3, 4.5];
console.log(pt[0]); // 3
console.log(pt[1]); // 4.5

// ── Tuple element write ──────────────────────────────────────────────────────

const mutable: [i32, i32] = [10, 20];
mutable[0] = 99;
console.log(mutable[0]); // 99
console.log(mutable[1]); // 20

// ── Tuple destructuring ──────────────────────────────────────────────────────

const src: [i32, f64] = [7, 3.14];
const [x, y] = src;
console.log(x); // 7
console.log(y); // 3.14

// ── Function returning a tuple ───────────────────────────────────────────────

function minMax(a: i32, b: i32): [i32, i32] {
  if (a < b) {
    return [a, b];
  }
  return [b, a];
}

const result = minMax(8, 3);
console.log(result[0]); // 3
console.log(result[1]); // 8

// Access via element index on return value
const result2 = minMax(42, 17);
console.log(result2[0]); // 17
console.log(result2[1]); // 42

// ── Function accepting a named tuple alias ───────────────────────────────────

function sumPair(p: Pair): i32 {
  return p[0] + p[1];
}

const addends: Pair = [6, 7];
console.log(sumPair(addends)); // 13

// ── Mixed-type tuple return ──────────────────────────────────────────────────

function divmod(a: i32, b: i32): [i32, i32] {
  const q: i32 = (a / b) | 0;
  const r: i32 = a % b;
  return [q, r];
}

const qr = divmod(17, 5);
console.log(qr[0]); // 3
console.log(qr[1]); // 2
