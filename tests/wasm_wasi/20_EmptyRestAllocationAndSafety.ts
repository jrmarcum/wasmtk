type i32 = number;

export function testEmptyRest(): void {
  console.log("--- Test 2: Empty Rest Array Safety ---");

  const smallPair: i32[] = [55, 66];

  // Unpacking matches total elements exactly
  const [first, second, ...remainder] = smallPair;

  console.log("First Element:", first);          // Expected: 55
  console.log("Second Element:", second);        // Expected: 66
  console.log("Remainder Length:", remainder.length); // Expected: 0

  // Mutating the empty rest array should safely expand it without corrupting the heap
  remainder.push(77);
  console.log("Post-Push Length:", remainder.length); // Expected: 1
  console.log("Post-Push Value:", remainder[0]);     // Expected: 77
}

testEmptyRest();