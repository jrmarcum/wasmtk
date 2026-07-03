// Phase 18 stress test — main application (compiled via wasic)
// Uses Phase 18 WASM import syntax so wasmmerge.ts performs structural unification:
//   1. Global & data segment relocation (dataOffset shift)
//   2. Namespace collision prevention ($__malloc, $__heap_ptr deduplication)
//   3. Import elimination — (import "env" "...") replaced with direct local calls
type i32 = number;

import { computeScaledArea, logLibraryVersion } from "./18_MathLibrary_Modc.wasm";

console.log("--- Test 1: Static Function Linkage ---");
// MathLib.computeScaledArea(10, 4) = ((10 * 4) >> 1) * libraryMultiplier(3) = 60
const areaResult: i32 = computeScaledArea(10, 4);
console.log("Scaled Area Result:", areaResult);

console.log("--- Test 2: Shifted Data Segment Pointers ---");
// The string "Library Version: v1.8.0-core" lives in the library's data section.
// wasmmerge must update the i32.const pointer inside logLibraryVersion by
// adding mainModule.dataOffset, or the output will be garbage / a WASI trap.
logLibraryVersion();
