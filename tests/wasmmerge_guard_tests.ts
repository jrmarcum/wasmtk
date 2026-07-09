/**
 * wasmmerge foreign-runtime guard — unit tests (no Go/TinyGo toolchain required).
 *
 * mergeWasmWat() must REJECT any module that carries its own growing allocator /
 * language runtime (detected by a `memory.grow` in the module) BEFORE it reaches
 * the per-function `call_indirect` guard, because merging a runtime module into
 * wasmtk's single shared linear memory would silently corrupt state once it
 * allocates. This is the signature of a STANDARD-Go WASI module (full runtime +
 * GC). A mergeable leaf (TinyGo `wasm-unknown`, FixedBufferAllocator, etc.) never
 * calls memory.grow and must NOT trip the guard.
 *
 * See cmem/polyglot-producers.md ("allocation is the gate") and
 * src/wasmmerge.ts (module-level memory.grow guard).
 */
import { assertThrows } from "jsr:@std/assert";
import { mergeWasmWat } from "../src/wasmmerge.ts";

// A module that grows its own memory — stands in for standard-Go / any full runtime.
const GROWING = `(module
  (func $grow (export "grow") (param $p i32) (result i32)
    (memory.grow (local.get $p)))
  (memory (export "memory") 1))`;

// An alloc-free leaf — stands in for a TinyGo wasm-unknown / FixedBufferAllocator lib.
const LEAF = `(module
  (func $addi (export "addi") (param $a i32) (param $b i32) (result i32)
    (i32.add (local.get $a) (local.get $b)))
  (memory (export "memory") 1))`;

Deno.test("mergeWasmWat rejects a growing (runtime) module with actionable guidance", () => {
  const err = assertThrows(
    () => mergeWasmWat(GROWING, "stdlib", 0),
    Error,
    "memory.grow",
  );
  const msg = String(err);
  // The message must name the real blocker (runtime/allocator) and the Go fix path,
  // NOT the red-herring call_indirect "refactor to direct calls" advice.
  if (!/growing allocator|language runtime/.test(msg)) {
    throw new Error("guard message must name the growing allocator / runtime");
  }
  if (!/STANDARD Go|wasm-unknown/.test(msg)) {
    throw new Error("guard message must point Go users at the mergeable-leaf path");
  }
  if (/refactor.*direct calls/i.test(msg)) {
    throw new Error("guard must not surface the call_indirect red herring for a runtime module");
  }
});

Deno.test("mergeWasmWat does NOT trip the runtime guard for an alloc-free leaf", () => {
  // The contract under test is precisely: memory.grow present -> throw; absent -> no throw.
  // (An alloc-free leaf — TinyGo wasm-unknown, FixedBufferAllocator — never grows memory.)
  // A well-formed leaf therefore merges without the runtime guard firing.
  mergeWasmWat(LEAF, "mathleaf", 0); // must not throw
});
