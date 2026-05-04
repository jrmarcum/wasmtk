// External runtime binding: 'logger' is declared via declare const and maps to WASM imports.
// Phase 40 upgrades this from @expect-fail: compile to a fully passing test.
// deno-lint-ignore-file
type i32 = number;

// Phase 40: declare const with inline object type → WASM import from "env"
declare const logger: { log(ptr: i32): void };

export function testExternalCall(msgPtr: i32): void {
  // Mapped to (import "env" "logger_log" (func $logger_log (param i32)))
  logger.log(msgPtr);
}

// Top-level code avoids calling the external binding (no host implementation available).
console.log("ok");
