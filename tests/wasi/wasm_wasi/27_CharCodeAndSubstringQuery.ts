type i32 = number;

export function testCharacterAccessAndQuery(): void {
  console.log("--- Test 3: Char Code & Substring Queries ---");

  const word: string = "WebAssembly";

  const firstCode: i32 = word.charCodeAt(0);
  const firstChar: string = word.charAt(0);

  console.log("ASCII Code 0:", firstCode); // Expected: 87 ('W')
  console.log("Char At 0:", firstChar); // Expected: "W"

  const starts: boolean = word.startsWith("Web");
  const ends: boolean = word.endsWith("bly");
  const falseEnds: boolean = word.endsWith("xyz");

  console.log("Starts With 'Web':", starts ? 1 : 0); // Expected: 1
  console.log("Ends With 'bly':", ends ? 1 : 0); // Expected: 1
  console.log("Ends With 'xyz':", falseEnds ? 1 : 0); // Expected: 0
}

testCharacterAccessAndQuery();
