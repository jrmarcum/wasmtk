// Phase 51: single-PHYSICAL-line class and constructor bodies now parse fully — fields that share
// a line with the constructor/methods are registered, and multi-statement single-line bodies
// (e.g. `super(k); this.v = v;`) are split into statements instead of being mangled into one.
// Previously these emitted empty constructors / unparsed fields; the workaround was multi-line
// class bodies. Self-checking via the check()/guard trap pattern.

// deno-fmt-ignore-file -- keep the single-physical-line class/constructor forms under test intact

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

// Whole class body on one physical line: field + constructor + method.
class Animal { age: i32; constructor(a: i32) { this.age = a; } describe(): i32 { return this.age; } }

// Single-line subclass: multi-statement constructor (super(...) + field assignment).
class Dog extends Animal { legs: i32; constructor(a: i32, l: i32) { super(a); this.legs = l; } }

// Multiple fields on the shared line, plus a single-line method with control flow.
class Point { x: i32; y: i32; constructor(a: i32, b: i32) { this.x = a; this.y = b; } maxc(): i32 { if (this.x > this.y) { return this.x; } return this.y; } }

function main(): void {
  const a: Animal = new Animal(11);
  check(a.age === 11 ? 1 : 0);
  check(a.describe() === 11 ? 1 : 0);

  const d: Dog = new Dog(3, 4);
  check(d.age === 3 ? 1 : 0); // inherited field set via super(a)
  check(d.legs === 4 ? 1 : 0); // own field set after super
  check(d instanceof Animal ? 1 : 0);
  check(d instanceof Dog ? 1 : 0);

  const base: Animal = new Dog(7, 2);
  check(base instanceof Dog ? 1 : 0); // runtime tag from single-line ctor

  const p: Point = new Point(3, 9);
  check(p.x === 3 ? 1 : 0);
  check(p.y === 9 ? 1 : 0);
  check(p.maxc() === 9 ? 1 : 0); // single-line method with if + trailing return

  console.log("age:", a.age, "legs:", d.legs, "max:", p.maxc());
  console.log("single-line class body ok");
}

main();
