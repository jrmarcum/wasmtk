type i32 = number;
type f64 = number;

// Phase 29: string-valued enum
enum Direction {
  Up = "up",
  Down = "down",
  Left = "left",
  Right = "right"
}

// Phase 29: class with static field, getters, and setters
class Rectangle {
  _width: f64;
  _height: f64;
  static count: i32 = 0;

  constructor(w: f64, h: f64) {
    this._width = w;
    this._height = h;
    Rectangle.count = Rectangle.count + 1;
  }

  get width(): f64 {
    return this._width;
  }

  set width(val: f64) {
    this._width = val;
  }

  get area(): f64 {
    return this._width * this._height;
  }

  static getCount(): i32 {
    return Rectangle.count;
  }
}

function main(): void {
  // String enum: assign to string variable
  const dir: string = Direction.Up;
  console.log("Direction:", dir);            // Direction: up

  // String enum: direct in console.log
  console.log(Direction.Down);               // down

  // Static field: incremented by constructor
  const r1: Rectangle = new Rectangle(3.0, 4.0);
  const r2: Rectangle = new Rectangle(5.0, 6.0);
  console.log("Count:", Rectangle.count);    // Count: 2

  // Static method reading static field
  console.log("Static:", Rectangle.getCount()); // Static: 2

  // Getter: read computed property
  console.log("Width:", r1.width);           // Width: 3
  console.log("Area:", r1.area);             // Area: 12

  // Setter: write computed property
  r1.width = 10.0;
  console.log("New width:", r1.width);       // New width: 10
  console.log("New area:", r1.area);         // New area: 40
}

main();
