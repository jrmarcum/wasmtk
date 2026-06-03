// Core_WASI_Strings.ts
export function _start(): void {
  // Test 1: Empty string
  console.log(""); 
  
  // Test 2: Very long string (tests buffer boundary)
  console.log("This is a significantly longer string designed to test if the compiler correctly calculates the byte length in the WASM data section or dynamic memory.");

  // Test 3: Multiple types in sequence
  const val = 42;
  console.log("Value is: ");
  console.log(val);
}

_start();