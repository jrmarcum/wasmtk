// Phase 29: Static Fields
// Tests: static field init, increment in constructor, multiple classes,
//        console.log of static field directly, read via static method,
//        static field write outside constructor, f64 static field.
type i32 = number;
type f64 = number;

class Widget {
  id: i32;
  static count: i32 = 0;
  static totalValue: f64 = 0.0;

  constructor(id: i32, value: f64) {
    this.id = id;
    Widget.count = Widget.count + 1;
    Widget.totalValue = Widget.totalValue + value;
  }

  static reset(): void {
    Widget.count = 0;
    Widget.totalValue = 0.0;
  }

  static getCount(): i32 {
    return Widget.count;
  }

  static getTotal(): f64 {
    return Widget.totalValue;
  }
}

class Box {
  static instances: i32 = 10;
}

function main(): void {
  // static fields start at declared init values before construction
  console.log(Widget.count);       // 0
  console.log(Widget.totalValue);  // 0

  const w1: Widget = new Widget(1, 1.5);
  const w2: Widget = new Widget(2, 2.5);
  const w3: Widget = new Widget(3, 3.0);

  // direct static field access after 3 constructions
  console.log(Widget.count);        // 3
  console.log(Widget.totalValue);   // 7

  // via static method
  console.log(Widget.getCount());   // 3
  console.log(Widget.getTotal());   // 7

  // reset and verify
  Widget.reset();
  console.log(Widget.count);        // 0
  console.log(Widget.totalValue);   // 0

  // independent static field on another class
  console.log(Box.instances);       // 10

  // manually write a static field
  Box.instances = 42;
  console.log(Box.instances);       // 42
}

main();
