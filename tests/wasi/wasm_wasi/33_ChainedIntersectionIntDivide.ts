// Phase 33 — Intersection types: three-way chain (A & B & C) passed as a function
// parameter, with an integer divide over two merged fields.
type i32 = number;

interface HasName {
  code: i32;
}

interface HasDimensions {
  width: i32;
  height: i32;
}

interface HasWeight {
  mass: i32;
}

// Multi-way intersection chain
type HeavyBox = HasName & HasDimensions & HasWeight;

function calculateDensity(box: HeavyBox): i32 {
  const volume = box.width * box.height;
  return box.mass / volume;
}

export function testChainedIntersection(): void {
  console.log("--- Test 2: Chained Multi-Way Intersection ---");

  const box: HeavyBox = {
    code: 99,
    width: 2,
    height: 5,
    mass: 100
  };

  console.log("Box Code:", box.code);                 // Expected: 99
  console.log("Calculated Density:", calculateDensity(box)); // Expected: 100 / 10 = 10
}

testChainedIntersection();
