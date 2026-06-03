type i32 = number;

export function testLexicalCapture(multiplier: i32): i32 {
  // Capture 'multiplier' from the local scope
  const simpleScale = (val: i32): i32 => val * multiplier;
  return simpleScale(10);
}

console.log(testLexicalCapture(5)); // Output: 50