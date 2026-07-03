// Phase 51: instanceof narrowing — inside `if (x instanceof Sub)` the variable narrows to Sub,
// so subclass-only methods/fields resolve. Exercises a base-typed function parameter (the case
// where the concrete type is NOT known statically and the runtime tag must drive both the
// branch selection and the narrowed dispatch).

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

// Base-typed parameter: concrete type unknown until runtime. The instanceof narrows `s` so the
// subclass field (s.side / s.r) is readable inside each branch.
function describe(s: Shape): i32 {
  if (s instanceof Square) {
    return s.side * 10;
  }
  if (s instanceof Circle) {
    return s.r * 100;
  }
  return -1;
}

function main(): void {
  const sq: Square = new Square(1, 4);
  const ci: Circle = new Circle(2, 5);
  const sh: Shape = new Shape(3);

  check(describe(sq) === 40 ? 1 : 0);
  check(describe(ci) === 500 ? 1 : 0);
  check(describe(sh) === -1 ? 1 : 0);

  // Narrowing also works on a base-typed local pointing at a subclass instance.
  const poly: Shape = new Square(9, 6);
  check(poly instanceof Square ? 1 : 0);
  if (poly instanceof Square) {
    check(poly.side === 6 ? 1 : 0);
  }

  console.log("describe sq:", describe(sq));
  console.log("describe ci:", describe(ci));
  console.log("narrowing instanceof ok");
}

main();
