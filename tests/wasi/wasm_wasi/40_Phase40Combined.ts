// Phase 40: combined — multiple declare interface + declare const bindings.
// deno-lint-ignore-file
type i32 = number;
type f64 = number;

declare interface Display {
  show(value: i32): void;
  clear(): void;
}

declare interface Sensor {
  read(): f64;
  calibrate(offset: f64): void;
}

declare const display: Display;
declare const sensor: Sensor;

export function readAndDisplay(): void {
  sensor.calibrate(0.5);
  display.show(42);
}

export function clearAll(): void {
  display.clear();
}

export function readSensor(): f64 {
  return sensor.read();
}

console.log(33);
