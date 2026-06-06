// Phase 51 (gap #1 fix): module-level class instances are now constructed AND tracked — field
// access, inherited fields, method dispatch, and instanceof all work at module scope (previously
// class code had to live inside a function). Self-checking via the check()/guard trap pattern.

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

class Animal {
  age: i32;
  constructor(a: i32) {
    this.age = a;
  }
  describe(): i32 {
    return this.age;
  }
}

class Dog extends Animal {
  legs: i32;
  constructor(a: i32, l: i32) {
    super(a);
    this.legs = l;
  }
}

// Class instances created at MODULE scope (no enclosing function).
const d: Animal = new Dog(3, 4);
const plain: Animal = new Animal(9);

check(d.age === 3 ? 1 : 0); // inherited field set by super(a)
check(d instanceof Dog ? 1 : 0); // runtime tag at module scope
check(d instanceof Animal ? 1 : 0);
check(plain instanceof Dog ? 0 : 1);
check(d.describe() === 3 ? 1 : 0); // inherited method dispatch at module scope

console.log("d.age:", d.age);
console.log("d is Dog:", d instanceof Dog);
console.log("module-level class instance ok");
