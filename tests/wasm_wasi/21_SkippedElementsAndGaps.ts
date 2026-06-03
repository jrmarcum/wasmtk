type i32 = number;

export function testSkippedTupleElements(): void {
  console.log("--- Test 2: Skipped Elements & Gaps ---");

  const coordinates: [i32, i32, i32, i32] = [10, 999, 20, 888];

  // Skipping the second and fourth indices completely using syntax gaps
  const [coordX, , coordY] = coordinates;

  console.log("Extracted X:", coordX); // Expected: 10
  console.log("Extracted Y:", coordY); // Expected: 20
}

testSkippedTupleElements();