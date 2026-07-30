type i32 = number;
type f64 = number;

interface Point2D {
  x: f64;
  y: f64;
}

interface LabeledPoint3D extends Point2D {
  z: f64;
  id: i32;
}

function processPoint(pt: LabeledPoint3D): f64 {
  return pt.x + pt.y + pt.z + (pt.id as f64);
}

export function testInterfaceInheritance(): void {
  console.log("--- Test 2: Interface Inheritance ---");

  const point: LabeledPoint3D = {
    x: 1.5,
    y: 2.5,
    z: 3.0,
    id: 10,
  };

  console.log("Point ID:", point.id); // Expected: 10
  console.log("Combined Sum:", processPoint(point)); // Expected: 1.5 + 2.5 + 3.0 + 10 = 17
}

testInterfaceInheritance();
