// VariableShadowing.ts
// Tests that a closure captures its outer variable even when other locals
// with different names hold different values in the same scope.
// Note: true block-scoped variable shadowing (same name as a param) is not
// supported — WASM locals are function-scoped and cannot redeclare a param name.
type i32 = number;
export function testShadowing(x: i32): i32 {
  const getX = (): i32 => x;
  const inner: i32 = 100; // different name — does not shadow x
  return getX(); // should return x, not inner
}

console.log(testShadowing(42)); // Should print 42
