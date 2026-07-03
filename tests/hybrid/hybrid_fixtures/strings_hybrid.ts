// Hybrid example with string params + async (skipped) function

// @wasm
export function greet(name: string): string {
  return "Hello, " + name + "!";
}

// @wasm
export function strLen(s: string): i32 {
  return s.length;
}

// @wasm — async: should be skipped with a warning
async function fetchRemote(): Promise<string> {
  return "data";
}

// Runtime side
const msg = greet("World");
const len = strLen("test");
console.log(msg);
console.log("len:", len);
