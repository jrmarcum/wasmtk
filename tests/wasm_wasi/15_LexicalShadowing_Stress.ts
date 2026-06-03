export function testLexicalShadowing(): void {
  const e: string = "Outer String";

  try {
    try {
      throw "Inner Literal Error"; // Throwing raw literal string[cite: 25]
    } catch (e) {
      // The variable 'e' here shadows the outer string[cite: 25]
      console.log("Inner Catch:", e); 
      throw e; // Re-throwing a dynamic string variable payload[cite: 25]
    }
  } catch (outerError) {
    console.log("Outer Catch:", outerError);
    console.log("Shadow Check:", e); // Should safely evaluate to "Outer String"
  }
}

console.log("--- Test 2: Lexical Scope Shadowing ---");
testLexicalShadowing();