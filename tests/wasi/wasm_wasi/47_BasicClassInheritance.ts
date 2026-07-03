// Phase 47: basic class inheritance — field layout and method dispatch
type i32 = number;
type f64 = number;

class Animal {
  age: i32;
  weight: f64;

  constructor(a: i32, w: f64) {
    this.age = a;
    this.weight = w;
  }

  describe(): void {
    console.log("Age:", this.age);
    console.log("Weight:", this.weight);
  }
}

class Dog extends Animal {
  legs: i32;

  constructor(a: i32, w: f64, l: i32) {
    super(a, w);
    this.legs = l;
  }

  bark(): void {
    console.log("Woof! Legs:", this.legs);
  }
}

function main(): void {
  const d: Dog = new Dog(3, 15.5, 4);
  d.describe();
  d.bark();
  console.log(d.age);
  console.log(d.weight);
  console.log(d.legs);
}

main();
// Expected output:
// Age: 3
// Weight: 15.5
// Woof! Legs: 4
// 3
// 15.5
// 4
