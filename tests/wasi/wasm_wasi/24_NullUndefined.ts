/**
 * Phase 24: null / undefined as values; T | null returns
 *
 * Covered:
 *   - Nullable variable declaration:  const x: i32 | null = null
 *   - Nullable variable with value:   const y: i32 | null = 42
 *   - Nullable reassignment to null:  x = null
 *   - Nullable reassignment to value: x = 10
 *   - Null check with if:             if (x === null)
 *   - Nullable function return type:  function maybeGet(flag: i32): i32 | null
 *   - Return null from function
 *   - Return value from function
 *   - Consuming nullable return value
 *   - console.log of nullable var (prints "null" or value)
 */

type i32 = number;
type f64 = number;

// ── Basic nullable declaration ────────────────────────────────────────────────

const a: i32 | null = null;
if (a === null) {
  console.log("a is null"); // a is null
}

const b: i32 | null = 99;
if (b !== null) {
  console.log(b); // 99
}

// ── console.log of nullable var ───────────────────────────────────────────────

const c: i32 | null = null;
console.log(c); // null

const d: i32 | null = 7;
console.log(d); // 7

// ── Nullable reassignment ─────────────────────────────────────────────────────

let e: i32 | null = 5;
console.log(e); // 5
e = null;
console.log(e); // null
e = 42;
console.log(e); // 42

// ── Nullable f64 variable ─────────────────────────────────────────────────────

const fv: f64 | null = null;
if (fv === null) {
  console.log("fv is null"); // fv is null
}

const gv: f64 | null = 3.14;
if (gv !== null) {
  console.log(gv); // 3.14
}

// ── Nullable function return type ─────────────────────────────────────────────

function maybeGet(flag: i32): i32 | null {
  if (flag) {
    return 100;
  }
  return null;
}

const r1: i32 | null = maybeGet(1);
if (r1 !== null) {
  console.log(r1); // 100
}

const r2: i32 | null = maybeGet(0);
if (r2 === null) {
  console.log("r2 is null"); // r2 is null
}
