// Phase 51: instanceof — runtime class-tag check across an inheritance hierarchy.
//
// Self-checking: each expectation calls check(); on the first wrong result check() reads far
// out of bounds, trapping the module so the `run` step exits non-zero and the test fails.
// (A wasic uncaught `throw` exits 0 by design, so it cannot be used to fail a pipeline.)
// Class instances are created inside a function (module-level class instances are not supported).

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
}

class Dog extends Animal {
  constructor(a: i32) {
    super(a);
  }
}

class Cat extends Animal {
  constructor(a: i32) {
    super(a);
  }
}

class Puppy extends Dog {
  constructor(a: i32) {
    super(a);
  }
}

function main(): void {
  // Base-typed variable holding a concrete subclass — runtime tag is the source of truth.
  const d: Animal = new Dog(3);
  const c: Animal = new Cat(5);
  const p: Animal = new Puppy(1);

  // d is a Dog and (transitively) an Animal, but not a Cat or a Puppy.
  check(d instanceof Dog ? 1 : 0);
  check(d instanceof Animal ? 1 : 0);
  check(d instanceof Cat ? 0 : 1);
  check(d instanceof Puppy ? 0 : 1);

  // c is a Cat and an Animal, but not a Dog.
  check(c instanceof Cat ? 1 : 0);
  check(c instanceof Animal ? 1 : 0);
  check(c instanceof Dog ? 0 : 1);

  // p is a Puppy, which extends Dog which extends Animal — instanceof of any ancestor is true.
  check(p instanceof Puppy ? 1 : 0);
  check(p instanceof Dog ? 1 : 0);
  check(p instanceof Animal ? 1 : 0);
  check(p instanceof Cat ? 0 : 1);

  // Concrete-typed variable.
  const realDog: Dog = new Dog(7);
  check(realDog instanceof Dog ? 1 : 0);
  check(realDog instanceof Animal ? 1 : 0);

  // console.log of an instanceof expression prints true/false.
  console.log("d instanceof Dog:", d instanceof Dog);
  console.log("d instanceof Cat:", d instanceof Cat);
  console.log("p instanceof Animal:", p instanceof Animal);

  console.log("basic instanceof ok");
}

main();
