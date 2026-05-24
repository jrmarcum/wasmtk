// Phase 47: super() constructor chaining across 3 levels
type i32 = number;
type f64 = number;

class Vehicle {
  speed: i32;
  fuel: f64;

  constructor(s: i32, f: f64) {
    this.speed = s;
    this.fuel = f;
  }
}

class Car extends Vehicle {
  doors: i32;

  constructor(s: i32, f: f64, d: i32) {
    super(s, f);
    this.doors = d;
  }
}

class SportsCar extends Car {
  turbo: i32;

  constructor(s: i32, f: f64, d: i32, t: i32) {
    super(s, f, d);
    this.turbo = t;
  }
}

function main(): void {
  const sc: SportsCar = new SportsCar(200, 60.5, 2, 1);
  console.log(sc.speed);
  console.log(sc.fuel);
  console.log(sc.doors);
  console.log(sc.turbo);

  const c: Car = new Car(150, 45.0, 4);
  console.log(c.speed);
  console.log(c.fuel);
  console.log(c.doors);
}

main();
// Expected output:
// 200
// 60.5
// 2
// 1
// 150
// 45
// 4
