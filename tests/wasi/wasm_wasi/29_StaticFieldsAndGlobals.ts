type i32 = number;

class CounterNode {
  static totalInstances: i32 = 0;
  id: i32;

  constructor(id: i32) {
    this.id = id;
    CounterNode.totalInstances += 1; // Mutating static global inside constructor
  }

  static getCount(): i32 {
    return CounterNode.totalInstances; // Reading static global inside static method
  }
}

export function testStaticFields(): void {
  console.log("--- Test 1: Static Fields & Globals ---");

  console.log("Initial Static Count:", CounterNode.getCount()); // Expected: 0

  const n1 = new CounterNode(101);
  const n2 = new CounterNode(102);

  console.log("Updated Static Count:", CounterNode.getCount()); // Expected: 2
  console.log("Direct Static Field Access:", CounterNode.totalInstances); // Expected: 2
}

testStaticFields();
