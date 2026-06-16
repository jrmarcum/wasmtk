// A hybrid fixture exercising ASYNC @wasm functions routed into the wasic core (Phase 13.5).
// async functions used to be skipped; now wasic compiles async/await, so they are routed via a
// synchronous unwrapping wrapper in the core module. The host calls them through `lib` as normal.

// @wasm
async function step1(x: i32): Promise<i32> {
  return x + 1;
}

// @wasm
async function process(data: i32): Promise<i32> {
  const a: i32 = await step1(data);
  return a * 10;
}

// @wasm
async function scale(x: f64): Promise<f64> {
  return x * 2.5;
}

// Runtime-only host code — stays in TypeScript.
function describe(label: string, value: unknown): void {
  console.log(`${label}: ${value}`);
}

const r: i32 = await process(4);
const s: f64 = await scale(2.0);

describe("process(4)", r);
describe("scale(2.0)", s);
