// Phase 34 — Type predicates: standalone if/else-if chains with narrowing
type i32 = number;
type f64 = number;

interface Vehicle {
  kind: i32;
  speed: f64;
}

interface Car extends Vehicle {
  doors: i32;
}

interface Truck extends Vehicle {
  payload: f64;
}

interface Bike extends Vehicle {
  electric: i32;
}

function isCar(v: Vehicle): v is Car {
  return v.kind === 1;
}

function isTruck(v: Vehicle): v is Truck {
  return v.kind === 2;
}

function isBike(v: Vehicle): v is Bike {
  return v.kind === 3;
}

function describeVehicle(v: Vehicle): void {
  if (isCar(v)) {
    console.log("car doors:", v.doors);      // accesses Car.doors via narrowing
    console.log("car speed:", v.speed);      // inherited field always accessible
  } else if (isTruck(v)) {
    console.log("truck payload:", v.payload); // accesses Truck.payload via narrowing
  } else if (isBike(v)) {
    console.log("bike electric:", v.electric); // accesses Bike.electric via narrowing
  } else {
    console.log("unknown vehicle");
  }
}

function main(): void {
  const car: Car   = { kind: 1, speed: 120.0, doors: 4 };
  const truck: Truck = { kind: 2, speed: 80.0, payload: 5000.0 };
  const bike: Bike   = { kind: 3, speed: 25.0, electric: 1 };
  const v: Vehicle   = { kind: 9, speed: 0.0 };

  // Bool return values
  console.log(isCar(car));     // true
  console.log(isTruck(bike));  // false
  console.log(isBike(bike));   // true

  // Narrowing in else-if chains
  describeVehicle(car);   // car doors: 4 / car speed: 120
  describeVehicle(truck); // truck payload: 5000
  describeVehicle(bike);  // bike electric: 1
  describeVehicle(v);     // unknown vehicle
}

main();
