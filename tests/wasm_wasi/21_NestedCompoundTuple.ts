type i32 = number;

class NodeMetric {
  id: i32;
  // A tuple nested inside a class object layout
  bounds: [i32, i32];

  constructor(id: i32, min: i32, max: i32) {
    this.id = id;
    this.bounds = [min, max];
  }
}

export function testNestedTuple(): void {
  console.log("--- Test 3: Nested Compound Tuple ---");

  const metric = new NodeMetric(7, 150, 300);

  // Destructuring a tuple extracted directly from a parent object reference path
  const [lower, upper] = metric.bounds;

  console.log("Metric Node ID:", metric.id); // Expected: 7
  console.log("Lower Bound Value:", lower);  // Expected: 150
  console.log("Upper Bound Value:", upper);  // Expected: 300
}

testNestedTuple();