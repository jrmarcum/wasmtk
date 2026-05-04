// Phase 41: WIT generation covers all wasic numeric return types.
// deno-lint-ignore-file
type i32 = number;
type i64 = bigint;
type f32 = number;
type f64 = number;
type bool = boolean;

export function getInt(): i32 {
  return 42;
}

export function getFloat(): f64 {
  return 3.14;
}

export function getFlag(): bool {
  return true;
}

export function noReturn(): void {
  const _x: i32 = 1;
}

console.log(getInt());
