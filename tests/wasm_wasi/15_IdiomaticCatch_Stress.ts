export function testIdiomaticCatch(): void {
  try {
    throw new Error("Structural Error Message"); // Standard exception object throw[cite: 25]
  } catch (e) {
    // Validates idiomatic catch block string conversion ternary routing[cite: 25]
    const msg1: string = e instanceof Error ? e.message : String(e); //[cite: 25]
    const msg2: string = String(e); //[cite: 25]

    console.log("Ternary Result:", msg1);
    console.log("String Result:", msg2);
  }
}

console.log("--- Test 3: Idiomatic Checking ---");
testIdiomaticCatch();