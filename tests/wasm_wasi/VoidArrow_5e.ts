// VoidArrow.ts
// Tests that void-return arrows (no return value) compile and run correctly.
// Note: in the current WASM value-passing model, void arrows cannot mutate
// captured outer variables — captures are passed by value, not by reference.
type i32 = number;
export function testVoidArrow(): i32 {
  // Void arrow with no params or captures
  const noOp = (): void => { };
  noOp();

  // Void arrow that accepts a param but returns nothing
  const sink = (n: i32): void => { };
  sink(42);
  sink(99);

  // Execution reaching here means void arrows didn't break control flow
  return 1;
}

console.log(testVoidArrow()); // Should output 1
