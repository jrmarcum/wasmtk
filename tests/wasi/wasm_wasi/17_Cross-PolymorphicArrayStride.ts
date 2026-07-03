type i32 = number;

class Shape {
  sides: i32;
  constructor(s: i32) {
    this.sides = s;
  }
  getArea(): i32 {
    return 0;
  }
}

class Square extends Shape {
  length: i32;
  constructor(l: i32) {
    super(4);
    this.length = l;
  }
  override getArea(): i32 {
    return this.length * this.length;
  }
}

class Rectangle extends Shape {
  width: i32;
  height: i32;
  constructor(w: i32, h: i32) {
    super(4);
    this.width = w;
    this.height = h;
  }
  override getArea(): i32 {
    return this.width * this.height;
  }
}

export function testPolymorphicArray(): void {
  console.log("--- Test 3: Polymorphic Array Stride ---");

  // An array of base class references holding varying size child structures
  // Shape (4 bytes), Square (8 bytes), Rectangle (12 bytes)
  const inventory: Shape[] = [];
  
  inventory.push(new Square(5));
  inventory.push(new Rectangle(4, 6));
  inventory.push(new Shape(0));

  let totalArea: i32 = 0;
  for (let i = 0; i < inventory.length; i++) {
    totalArea += inventory[i].getArea(); // Dynamic dispatch lookup on each element pointer
  }

  console.log("Total Combined Area:", totalArea); // Expected: 25 + 24 + 0 = 49
}

testPolymorphicArray();