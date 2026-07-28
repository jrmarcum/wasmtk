type i32 = number;

export function testDestructuringDefaults(): void {
  console.log("--- Test 2: Destructuring Defaults ---");

  // Array has only 1 element
  const partialArr: i32[] = [100];

  // b and c fall back to defaults
  const [a = 1, b = 2, c = 3] = partialArr;

  console.log("Element A (Present):", a); // Expected: 100
  console.log("Element B (Default):", b); // Expected: 2
  console.log("Element C (Default):", c); // Expected: 3
}

testDestructuringDefaults();
