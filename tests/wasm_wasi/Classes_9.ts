type i32 = number;
type f64 = number;

class Counter {
  count: i32;

  constructor(start: i32) {
    this.count = start;
  }

  increment(): void {
    this.count = this.count + 1;
  }

  decrement(): void {
    this.count = this.count - 1;
  }

  getCount(): i32 {
    return this.count;
  }

  static create(initial: i32): i32 {
    // returns initial value (static utility)
    return initial * 2;
  }
}

class Point {
  x: f64;
  y: f64;

  constructor(x: f64, y: f64) {
    this.x = x;
    this.y = y;
  }

  distanceSquared(): f64 {
    return this.x * this.x + this.y * this.y;
  }

  scale(factor: f64): void {
    this.x = this.x * factor;
    this.y = this.y * factor;
  }
}

function main(): void {
  const c: Counter = new Counter(10);
  c.increment();
  c.increment();
  c.increment();
  c.decrement();
  console.log("Counter:", c.getCount());  // 12

  const doubled = Counter.create(5);
  console.log("Static doubled:", doubled);  // 10

  const p: Point = new Point(3.0, 4.0);
  const distSq: f64 = p.distanceSquared();
  console.log("Distance squared:", distSq);  // 25.0

  p.scale(2.0);
  console.log("Scaled x:", p.x);  // 6.0
  console.log("Scaled y:", p.y);  // 8.0
}

main();
