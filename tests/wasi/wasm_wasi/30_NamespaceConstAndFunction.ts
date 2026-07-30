type i32 = number;

namespace PhysicsEngine {
  export const GRAVITY: i32 = 9;

  export function calculateForce(mass: i32): i32 {
    return mass * GRAVITY;
  }
}

export function testNamespaces(): void {
  console.log("--- Test 1: Namespaces ---");

  const force = PhysicsEngine.calculateForce(10);

  console.log("Constant Read:", PhysicsEngine.GRAVITY); // Expected: 9
  console.log("Calculated Force:", force); // Expected: 90
}

testNamespaces();
