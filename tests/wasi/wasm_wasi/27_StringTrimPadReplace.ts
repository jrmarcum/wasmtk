type i32 = number;

export function testStringTransformations(): void {
  console.log("--- Test 2: Trimming, Padding & Replacement ---");

  const padded: string = "   hello WASM   ";
  const trimmed: string = padded.trim();

  console.log("Trimmed:", trimmed); // Expected: "hello WASM"
  console.log("Padded Start:", trimmed.padStart(15, "*")); // Expected: "*****hello WASM"
  console.log("Repeated:", "x".repeat(3)); // Expected: "xxx"

  const rawText: string = "foo-bar-foo";
  const replacedOne: string = rawText.replace("foo", "baz");
  const replacedAll: string = rawText.replaceAll("foo", "baz");

  console.log("Replace First:", replacedOne); // Expected: "baz-bar-foo"
  console.log("Replace All:", replacedAll); // Expected: "baz-bar-baz"
}

testStringTransformations();
