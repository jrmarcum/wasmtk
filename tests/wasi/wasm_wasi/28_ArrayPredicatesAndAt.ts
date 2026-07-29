type i32 = number;

function isPositive(x: i32): boolean {
  return x > 0;
}

function isEven(x: i32): boolean {
  return x % 2 === 0;
}

export function testPredicatesAndAt(): void {
  console.log("--- Test 1: Array Predicates & at() ---");

  const numbers: i32[] = [2, 4, 6, 8, 10];

  const allPositive = numbers.every(isPositive);
  const hasEven = numbers.some(isEven);
  const firstMatchIdx = numbers.findIndex((x: i32) => x > 5);

  console.log("All Positive:", allPositive ? 1 : 0); // Expected: 1
  console.log("Has Even:", hasEven ? 1 : 0); // Expected: 1
  console.log("First Index > 5:", firstMatchIdx); // Expected: 2 (value 6)

  // Negative indexing via at()
  const lastElem = numbers.at(-1);
  const secondLast = numbers.at(-2);

  console.log("Last Element (-1):", lastElem); // Expected: 10
  console.log("Second Last (-2):", secondLast); // Expected: 8
}

testPredicatesAndAt();
