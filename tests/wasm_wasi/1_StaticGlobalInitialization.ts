// Core_Globals.ts
type f64 = number;
type i32 = number;
const PI: f64 = 3.14159;
let counter: i32 = 0;

export function _start(): void {
  counter = counter + 1;
  console.log(PI);
  console.log(counter);
}

_start();