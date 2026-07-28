type i32 = number;

let sideEffectCount: i32 = 0;

function computeValue(): i32 {
  sideEffectCount += 1;
  return 500;
}

export function testShortCircuiting(): void {
  console.log("--- Test 3: Short-Circuit Side Effects ---");

  let activeValue: i32 | null = 100;

  // Since activeValue is non-null, computeValue() MUST NOT be called
  activeValue ??= computeValue();

  console.log("Active Value:", activeValue); // Expected: 100
  console.log("Side Effect Count:", sideEffectCount); // Expected: 0

  let missingValue: i32 | null = null;

  // Since missingValue is null, computeValue() MUST be called
  missingValue ??= computeValue();

  console.log("Missing Value:", missingValue); // Expected: 500
  console.log("Side Effect Count:", sideEffectCount); // Expected: 1
}

testShortCircuiting();
