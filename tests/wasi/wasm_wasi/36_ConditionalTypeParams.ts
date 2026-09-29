// Phase 36 — Conditional types as function parameter and return types
type i32 = number;
type f64 = number;

// If T is i32 → f64; otherwise → i32
type NumCond<T> = T extends i32 ? f64 : i32;

function scale(val: NumCond<i32>): void {   // NumCond<i32> = f64
  console.log("scaled:", val * 3.0);
}

function count(val: NumCond<f64>): void {   // NumCond<f64> = i32
  console.log("count:", val + 1);
}

function main(): void {
  scale(2.5);   // scaled: 7.5
  count(4);     // count: 5
}

main();
