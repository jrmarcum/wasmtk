type i32 = number;

interface Vector {
  x: i32;
  y: i32;
}

function createVector(x: i32, y: i32): Vector {
  // Shorthand notation desugared at compile time to { x: x, y: y }
  return { x, y };
}

export function testShorthandProperties(): void {
  console.log("--- Test 3: Shorthand Properties ---");

  const vec = createVector(40, 60);

  console.log("Vector X:", vec.x); // Expected: 40
  console.log("Vector Y:", vec.y); // Expected: 60
}

testShorthandProperties();
