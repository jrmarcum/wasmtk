// Phase 29: Combined — static fields + getters/setters + string enums together
// Tests interaction of all three Phase 29 features in a single class hierarchy.
type i32 = number;
type f64 = number;

enum Shape {
  Circle = "circle",
  Square = "square",
  Triangle = "triangle"
}

class Circle {
  _radius: f64;
  static count: i32 = 0;

  constructor(r: f64) {
    this._radius = r;
    Circle.count = Circle.count + 1;
  }

  get radius(): f64 {
    return this._radius;
  }

  set radius(r: f64) {
    this._radius = r;
  }

  // approximate area: π ≈ 3.14159265
  get area(): f64 {
    return this._radius * this._radius * 3.14159265;
  }

  static getCount(): i32 {
    return Circle.count;
  }
}

class Square {
  _side: f64;
  static count: i32 = 0;

  constructor(s: f64) {
    this._side = s;
    Square.count = Square.count + 1;
  }

  get side(): f64 {
    return this._side;
  }

  set side(s: f64) {
    this._side = s;
  }

  get area(): f64 {
    return this._side * this._side;
  }

  get perimeter(): f64 {
    return this._side * 4.0;
  }

  static getCount(): i32 {
    return Square.count;
  }
}

function main(): void {
  // String enum usage
  console.log(Shape.Circle);    // circle
  console.log(Shape.Square);    // square

  const shapeType: string = Shape.Triangle;
  console.log(shapeType);       // triangle

  // Static field starts at 0 before any construction
  console.log(Circle.count);   // 0
  console.log(Square.count);   // 0

  // Create shapes
  const c1: Circle = new Circle(5.0);
  const c2: Circle = new Circle(3.0);
  const sq1: Square = new Square(4.0);

  // Static counts via direct access
  console.log(Circle.count);   // 2
  console.log(Square.count);   // 1

  // Static counts via method
  console.log(Circle.getCount());   // 2
  console.log(Square.getCount());   // 1

  // Getters: read-only computed property
  console.log(c1.radius);     // 5
  console.log(sq1.side);      // 4
  console.log(sq1.perimeter); // 16

  // Setter: update and re-read via getter
  c1.radius = 10.0;
  console.log(c1.radius);     // 10

  sq1.side = 6.0;
  console.log(sq1.side);      // 6
  console.log(sq1.area);      // 36
  console.log(sq1.perimeter); // 24
}

main();
