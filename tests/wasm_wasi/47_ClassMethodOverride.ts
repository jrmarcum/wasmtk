// Phase 47: method override across a 3-class hierarchy
type i32 = number;

class Shape {
  x: i32;

  constructor(x: i32) {
    this.x = x;
  }

  area(): i32 {
    return 0;
  }

  label(): void {
    console.log("Shape");
  }
}

class Circle extends Shape {
  radius: i32;

  constructor(x: i32, r: i32) {
    super(x);
    this.radius = r;
  }

  area(): i32 {
    return this.radius * this.radius * 3;
  }

  label(): void {
    console.log("Circle");
  }
}

class ColoredCircle extends Circle {
  color: i32;

  constructor(x: i32, r: i32, c: i32) {
    super(x, r);
    this.color = c;
  }

  area(): i32 {
    return this.radius * this.radius * 3 + this.color;
  }

  label(): void {
    console.log("ColoredCircle");
  }
}

function main(): void {
  const s: Shape = new Shape(0);
  const c: Circle = new Circle(0, 5);
  const cc: ColoredCircle = new ColoredCircle(0, 4, 10);

  s.label();
  c.label();
  cc.label();

  console.log(s.area());
  console.log(c.area());
  console.log(cc.area());

  // Inherited field access from Circle's parent (Shape)
  console.log(c.x);
  console.log(cc.x);
  console.log(cc.radius);
}

main();
// Expected output:
// Shape
// Circle
// ColoredCircle
// 0
// 75
// 58
// 0
// 0
// 4
