// A mixed TypeScript + WASM example.
// Functions annotated with // @wasm are compiled to WASM; the rest stays TypeScript.

// @wasm
export function add(a: i32, b: i32): i32 {
  return a + b;
}

// @wasm
export function multiply(a: f64, b: f64): f64 {
  return a * b;
}

// @wasm
export function isEven(n: i32): bool {
  return (n % 2) === 0;
}

// Runtime-only: uses template literals, console.log — stays in TypeScript
function describe(label: string, value: unknown): void {
  console.log(`${label}: ${value}`);
}

// Main entry point — calls @wasm functions through lib after hybrid split
const x = add(10, 32);
const y = multiply(3.0, 1.5);
const even = isEven(x);

describe("add(10, 32)", x);
describe("multiply(3.0, 1.5)", y);
describe("isEven(42)", even);
