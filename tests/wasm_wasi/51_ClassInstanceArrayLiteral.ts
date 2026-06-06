// Phase 51 (gap #2 fix): an array literal of `new` class instances is now constructed correctly.
// `const a: C[] = [new C(...), ...]` is desugared into `const a: C[] = []; a.push(new C(...));…`,
// so each element gets its constructor call + class tag (previously elements were zero-filled with
// no tag, so fields read 0 and instanceof was always false). Self-checking via check()/guard trap.

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

class Shape {
  id: i32;
  constructor(i: i32) {
    this.id = i;
  }
  area(): i32 {
    return 0;
  }
}

class Square extends Shape {
  side: i32;
  constructor(i: i32, s: i32) {
    super(i);
    this.side = s;
  }
  area(): i32 {
    return this.side * this.side;
  }
}

class Circle extends Shape {
  r: i32;
  constructor(i: i32, rad: i32) {
    super(i);
    this.r = rad;
  }
  area(): i32 {
    return 3 * this.r * this.r;
  }
}

function main(): void {
  // Array literal of mixed concrete subclasses — each element must be constructed + tagged.
  const shapes: Shape[] = [new Square(1, 4), new Circle(2, 5), new Square(3, 2)];

  check(shapes.length === 3 ? 1 : 0);

  // Constructed fields (inherited `id` from the base) are set per element.
  check(shapes[0].id === 1 ? 1 : 0);
  check(shapes[1].id === 2 ? 1 : 0);
  check(shapes[2].id === 3 ? 1 : 0);

  // instanceof on base-typed elements uses the runtime tag written by construction.
  check(shapes[0] instanceof Square ? 1 : 0);
  check(shapes[1] instanceof Circle ? 1 : 0);
  check(shapes[0] instanceof Circle ? 0 : 1);

  // Virtual method dispatch on array elements (Phase 47 vtable) over constructed instances.
  check(shapes[0].area() === 16 ? 1 : 0); // Square 4*4
  check(shapes[1].area() === 75 ? 1 : 0); // Circle 3*5*5
  check(shapes[2].area() === 4 ? 1 : 0); // Square 2*2

  // Count squares via instanceof over the array.
  let squares: i32 = 0;
  let k: i32 = 0;
  while (k < 3) {
    if (shapes[k] instanceof Square) {
      squares = squares + 1;
    }
    k = k + 1;
  }
  check(squares === 2 ? 1 : 0);

  console.log("squares:", squares);
  console.log("areas:", shapes[0].area(), shapes[1].area(), shapes[2].area());
  console.log("class-instance array literal ok");
}

main();
