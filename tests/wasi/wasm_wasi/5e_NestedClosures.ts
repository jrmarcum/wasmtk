// NestedClosures.ts
type i32 = number;
export function testNestedClosure(multiplier: i32): i32 {
  const firstLevel = (a: i32): i32 => {
    const secondLevel = (b: i32): i32 => {
      return a * b * multiplier;
    };
    return secondLevel(5);
  };
  return firstLevel(10);
}

console.log(testNestedClosure(2)); // Should output 100 (10 * 5 * 2)
