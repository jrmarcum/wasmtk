type i32 = number;

function getNullableValue(kind: i32): i32 | null {
  if (kind === 0) return null;
  if (kind === 1) return 0; // Falsy, but NOT null
  return 42;
}

export function testNullishCoalescing(): void {
  console.log("--- Test 1: Nullish Coalescing Semantics ---");

  const nullVal: i32 | null = getNullableValue(0);
  const zeroVal: i32 | null = getNullableValue(1);
  const realVal: i32 | null = getNullableValue(2);

  // Fallback triggers ONLY on null
  const res1 = nullVal ?? 999;
  const res2 = zeroVal ?? 999;
  const res3 = realVal ?? 999;

  console.log("Null Fallback:", res1); // Expected: 999
  console.log("Zero Fallback:", res2); // Expected: 0 (must NOT fall back)
  console.log("Real Fallback:", res3); // Expected: 42
}

testNullishCoalescing();
