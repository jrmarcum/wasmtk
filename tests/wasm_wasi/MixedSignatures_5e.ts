// MixedSignatures.ts
// Tests arrows with different parameter signatures assigned inside if/else branches.
// Type aliases for function types are not resolved by the compiler — use explicit
// inline function type annotations or fully-typed arrow declarations instead.
type i32 = number;

export function testMixedTable(op: i32): i32 {
  if (op == 1) {
    const add = (a: i32, b: i32): i32 => a + b;
    return add(10, 5);
  } else {
    const negate = (n: i32): i32 => 0 - n;
    return negate(10);
  }
}

console.log(testMixedTable(1)); // Should print 15
console.log(testMixedTable(2)); // Should print -10
