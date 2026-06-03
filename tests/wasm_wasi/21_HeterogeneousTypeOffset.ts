type i32 = number;
type f64 = number;

export function testHeterogeneousTuple(): void {
  console.log("--- Test 1: Heterogeneous Tuple Destructuring ---");

  // Represented on the heap as: [4 bytes i32] [4 bytes padding/alignment] [8 bytes f64] [1 byte bool]
  const record: [i32, f64, boolean] = [42, 3.14159, true];

  // Destructure into independent scalar values
  const [id, value, active] = record;

  console.log("Extracted ID:", id);         // Expected: 42
  console.log("Extracted Value:", value);   // Expected: 3.14159
  console.log("Extracted Active:", active ? 1 : 0); // Expected: 1
}

testHeterogeneousTuple();