// ClosureToClosure.ts
type i32 = number; // For clarity in this example
type Scaler = (val: i32) => i32;

export function testClosurePassing(initialMultiplier: i32): i32 {
  // 1. Create the first upward closure (allocated on heap)
  const baseScaler = (n: i32) => n * initialMultiplier;

  // 2. Pass that closure into a function that returns a NEW closure
  // This new closure CAPTURES the first closure pointer
  const doubleScaler = createDoubleScaler(baseScaler);

  // 3. Execute the resulting "wrapped" closure
  return doubleScaler(10); 
}

function createDoubleScaler(original: Scaler): Scaler {
  // This arrow function captures 'original' (which is itself a pointer)
  return (val: i32) => original(val) * 2;
}

console.log(testClosurePassing(5)); // Should output 100 (10 * 5 * 2)