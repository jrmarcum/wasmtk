type i32 = number;

export function safeDivide(a: i32, b: i32): i32 {
  if (b === 0) {
    // This should trigger a Wasm 'unreachable' or WASI 'proc_exit'
    throw new Error("Division by zero"); 
  }
  return a / b;
}

console.log(safeDivide(10, 2)); // Should print 5
console.log(safeDivide(10, 0)); // Should throw an error and trigger a trap