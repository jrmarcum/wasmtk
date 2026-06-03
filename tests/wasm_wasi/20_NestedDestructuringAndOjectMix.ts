type i32 = number;

interface Coordinate {
  x: i32;
  y: i32;
}

export function testNestedDestructuring(): void {
  console.log("--- Test 3: Nested Destructuring Mix ---");

  // A collection of structural interfaces
  const points: Coordinate[] = [
    { x: 1, y: 10 },
    { x: 2, y: 20 },
    { x: 3, y: 30 }
  ];

  // Unpack an item while catching the rest of the object reference pointers
  const [leadPoint, ...trailingPoints] = points;

  console.log("Lead X Coord:", leadPoint.x);               // Expected: 1
  console.log("Trailing Count:", trailingPoints.length);    // Expected: 2
  console.log("First Trailing Y:", trailingPoints[0].y);    // Expected: 20
}

testNestedDestructuring();