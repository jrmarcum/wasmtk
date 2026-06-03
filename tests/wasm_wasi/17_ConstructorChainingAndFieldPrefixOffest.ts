type i32 = number;

class Vector2D {
  x: i32;
  y: i32;

  constructor(x: i32, y: i32) {
    this.x = x;
    this.y = y;
  }
}

class Vector3D extends Vector2D {
  z: i32;

  constructor(x: i32, y: i32, z: i32) {
    // Force field initialization inside base routine first
    super(x, y); 
    this.z = z;
  }
}

class NamedVector3D extends Vector3D {
  id: i32; // Simulating string pointer or primitive identifier index

  constructor(x: i32, y: i32, z: i32, id: i32) {
    super(x, y, z);
    this.id = id;
  }

  printCoords(): void {
    // Accessing properties across all 3 levels of memory slices
    console.log("ID:", this.id);
    console.log("X:", this.x);
    console.log("Y:", this.y);
    console.log("Z:", this.z);
  }
}

export function testMemoryLayout(): void {
  console.log("--- Test 2: Field Offset Alignment ---");
  const vec = new NamedVector3D(11, 22, 33, 999);
  vec.printCoords();
}

testMemoryLayout();