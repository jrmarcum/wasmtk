// Phase 47: virtual dispatch — base-typed variable with concrete constructor
type i32 = number;

class Animal {
  age: i32;

  constructor(a: i32) {
    this.age = a;
  }

  speak(): void {
    console.log("...");
  }

  getAge(): i32 {
    return this.age;
  }
}

class Dog extends Animal {
  constructor(a: i32) {
    super(a);
  }

  speak(): void {
    console.log("Woof");
  }
}

class Cat extends Animal {
  constructor(a: i32) {
    super(a);
  }

  speak(): void {
    console.log("Meow");
  }
}

function main(): void {
  // Virtual dispatch: base-typed variable with concrete constructor
  const a1: Animal = new Dog(3);
  const a2: Animal = new Cat(5);
  a1.speak();
  a2.speak();

  // Inherited method via resolved concrete type
  console.log(a1.getAge());
  console.log(a2.getAge());

  // Concrete-typed dispatch still works
  const d: Dog = new Dog(7);
  const c: Cat = new Cat(9);
  d.speak();
  c.speak();
}

main();
// Expected output:
// Woof
// Meow
// 3
// 5
// Woof
// Meow
