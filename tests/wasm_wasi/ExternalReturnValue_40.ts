// Phase 40: external interface methods with i32 and f64 return values.
// deno-lint-ignore-file
type i32 = number;
type f64 = number;

declare const sensor: {
  readInt(): i32;
  readFloat(): f64;
  reset(): void;
};

export function getSensorInt(): i32 {
  return sensor.readInt();
}

export function getSensorFloat(): f64 {
  return sensor.readFloat();
}

export function resetSensor(): void {
  sensor.reset();
}

console.log(30);
