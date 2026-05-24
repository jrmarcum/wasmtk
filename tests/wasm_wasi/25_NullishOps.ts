/**
 * Phase 25: Optional chaining ?., nullish coalescing ??, logical assignment ??= ||= &&=
 *
 * Covered:
 *   - Nullish coalescing:           x ?? fallback
 *   - ?? with null variable
 *   - ?? with non-null variable (returns lhs)
 *   - Logical assignment ??=        x ??= value
 *   - Logical assignment ||=        x ||= value
 *   - Logical assignment &&=        x &&= value
 */

type i32 = number;
type f64 = number;

// ── Nullish coalescing ?? ─────────────────────────────────────────────────────

const a: i32 | null = null;
const r1: i32 = a ?? 55;
console.log(r1); // 55

const b: i32 | null = 7;
const r2: i32 = b ?? 99;
console.log(r2); // 7

// ── ?? with f64 nullable ──────────────────────────────────────────────────────

const fv: f64 | null = null;
const rf1: f64 = fv ?? 2.5;
console.log(rf1); // 2.5

const gv: f64 | null = 1.1;
const rf2: f64 = gv ?? 9.9;
console.log(rf2); // 1.1

// ── ??= (nullish assignment) ──────────────────────────────────────────────────

let x: i32 | null = null;
x ??= 10;
console.log(x); // 10

let y: i32 | null = 5;
y ??= 20;
console.log(y); // 5

// ── ||= (logical OR assignment) ───────────────────────────────────────────────

let p: i32 = 0;
p ||= 42;
console.log(p); // 42

let q: i32 = 7;
q ||= 99;
console.log(q); // 7

// ── &&= (logical AND assignment) ──────────────────────────────────────────────

let s: i32 = 1;
s &&= 88;
console.log(s); // 88

let t: i32 = 0;
t &&= 77;
console.log(t); // 0
