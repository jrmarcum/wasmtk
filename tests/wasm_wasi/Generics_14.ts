// Phase 14 — Generics (Monomorphization)
// Tests: explicit type args, literal inference, generic structs, generic func with struct param

// ── Generic identity ──────────────────────────────────────────────────────────

function identity<T>(x: T): T {
  return x;
}

// ── Generic min/max (two params, same type) ───────────────────────────────────

function minVal<T>(a: T, b: T): T {
  return a < b ? a : b;
}

function maxVal<T>(a: T, b: T): T {
  return a > b ? a : b;
}

// ── Generic struct ────────────────────────────────────────────────────────────

interface Box<T> {
  value: T;
  count: i32;
}

// ── Generic function consuming a generic struct param ─────────────────────────

function getBoxValue<T>(b: Box<T>): T {
  return b.value;
}

// ── All tests inside main() so structs use emitFunction's pre-scan ────────────

function main() {
  // Explicit type args
  const a1: i32 = identity<i32>(42);
  console.log(a1);           // 42
  const a2: f64 = identity<f64>(3.14);
  console.log(a2);           // 3.14
  const a3: bool = identity<bool>(true);
  console.log(a3);           // true

  // Inferred type from literal (single type param)
  const b1 = identity(99);
  console.log(b1);           // 99
  const b2 = identity(2.718);
  console.log(b2);           // 2.718

  // Multi-param generics
  const mn1: i32 = minVal<i32>(10, 20);
  console.log(mn1);          // 10
  const mn2: f64 = minVal<f64>(1.5, 2.5);
  console.log(mn2);          // 1.5
  const mx1: i32 = maxVal<i32>(10, 20);
  console.log(mx1);          // 20
  const mx2: f64 = maxVal<f64>(1.5, 2.5);
  console.log(mx2);          // 2.5

  // Generic struct: Box<i32>
  const box1: Box<i32> = { value: 99, count: 3 };
  console.log(box1.value);   // 99
  console.log(box1.count);   // 3

  // Generic struct: Box<f64>
  const box2: Box<f64> = { value: 1.618, count: 1 };
  console.log(box2.value);   // 1.618
  console.log(box2.count);   // 1

  // Generic function with generic struct param
  const bv: i32 = getBoxValue<i32>(box1);
  console.log(bv);           // 99
}

main();
