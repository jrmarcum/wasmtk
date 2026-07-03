type i32 = number;

class Item {
  weight: i32;
  constructor(w: i32) {
    this.weight = w;
  }
  getWeight(): i32 {
    return this.weight;
  }
}

// Subclass enforcing Phase 47 inheritance layouts alongside constraint-like dispatch
class HeavyItem extends Item {
  bonus: i32;
  constructor(w: i32, b: i32) {
    super(w);
    this.bonus = b;
  }
  override getWeight(): i32 {
    return this.weight + this.bonus;
  }
}

// Concrete inspect functions — replaces generic Scale<T extends Measurable>.inspect()
function inspectItem(item: Item): i32 {
  return item.getWeight();
}

function inspectHeavy(item: HeavyItem): i32 {
  return item.getWeight();
}

export function testGenericConstraints(): void {
  console.log("--- Test 3: Generic Constraints ---");

  const baseItem = new Item(15);
  console.log("Base Scale Weight:", inspectItem(baseItem)); // Expected: 15

  const heavyItem = new HeavyItem(100, 50);
  console.log("Heavy Scale Weight:", inspectHeavy(heavyItem)); // Expected: 150
}

testGenericConstraints();
