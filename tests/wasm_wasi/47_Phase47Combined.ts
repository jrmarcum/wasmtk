// Phase 47: combined test with two independent class hierarchies
type i32 = number;
type f64 = number;

// Hierarchy 1: Vehicle → Car → ElectricCar
class Vehicle {
  speed: i32;

  constructor(s: i32) {
    this.speed = s;
  }

  move(): void {
    console.log("Vehicle: Speed", this.speed);
  }

  maxSpeed(): i32 {
    return this.speed;
  }
}

class Car extends Vehicle {
  doors: i32;

  constructor(s: i32, d: i32) {
    super(s);
    this.doors = d;
  }

  move(): void {
    console.log("Car: Vroom at", this.speed);
  }
}

class ElectricCar extends Car {
  battery: i32;

  constructor(s: i32, d: i32, b: i32) {
    super(s, d);
    this.battery = b;
  }

  move(): void {
    console.log("ElectricCar: Silent at", this.speed);
  }
}

// Hierarchy 2: Node → LeafNode → BranchNode
class Node {
  value: i32;

  constructor(v: i32) {
    this.value = v;
  }

  getValue(): i32 {
    return this.value;
  }
}

class LeafNode extends Node {
  depth: i32;

  constructor(v: i32, d: i32) {
    super(v);
    this.depth = d;
  }
}

class BranchNode extends LeafNode {
  children: i32;

  constructor(v: i32, d: i32, c: i32) {
    super(v, d);
    this.children = c;
  }
}

function main(): void {
  // Hierarchy 1: concrete-typed dispatch
  const v: Vehicle = new Vehicle(100);
  const c: Car = new Car(200, 4);
  const ec: ElectricCar = new ElectricCar(150, 2, 80);
  v.move();
  c.move();
  ec.move();

  // Virtual dispatch: base-typed variables
  const v2: Vehicle = new Car(300, 4);
  const v3: Vehicle = new ElectricCar(250, 2, 100);
  v2.move();
  v3.move();

  // Inherited method via resolved concrete type
  console.log(ec.maxSpeed());
  console.log(v2.maxSpeed());

  // Hierarchy 2: multi-level super chain
  const b: BranchNode = new BranchNode(42, 3, 5);
  console.log(b.getValue());
  console.log(b.depth);
  console.log(b.children);
}

main();
// Expected output:
// Vehicle: Speed 100
// Car: Vroom at 200
// ElectricCar: Silent at 150
// Car: Vroom at 300
// ElectricCar: Silent at 250
// 150
// 300
// 42
// 3
// 5
