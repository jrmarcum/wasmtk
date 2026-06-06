// Phase 51: instanceof with no inheritance in the module — there is no runtime tag header, so the
// test is resolved at compile time from the variable's statically-tracked class.

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

class Box {
  v: i32;
  constructor(x: i32) {
    this.v = x;
  }
}

class Bag {
  w: i32;
  constructor(x: i32) {
    this.w = x;
  }
}

function main(): void {
  const b: Box = new Box(7);
  const g: Bag = new Bag(9);

  // Compile-time true / false (no inheritance → each var is exactly its own class).
  check(b instanceof Box ? 1 : 0);
  check(b instanceof Bag ? 0 : 1);
  check(g instanceof Bag ? 1 : 0);
  check(g instanceof Box ? 0 : 1);

  // instanceof result assigned to a boolean local, then used.
  const bIsBox: boolean = b instanceof Box;
  const bIsBag: boolean = b instanceof Bag;
  check(bIsBox ? 1 : 0);
  check(bIsBag ? 0 : 1);

  console.log("b instanceof Box:", b instanceof Box);
  console.log("b instanceof Bag:", b instanceof Bag);
  console.log("no-inheritance instanceof ok");
}

main();
