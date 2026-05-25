// Phase 18 stress test — library module (compiled via modc)
// Tests: global relocation (libraryMultiplier) + data segment relocation (version string)
type i32 = number;

// Internal library-scoped global — tests global index shifting after merge
const libraryMultiplier: i32 = 3;

/** @export */
export function computeScaledArea(base: i32, height: i32): i32 {
  // Use integer arithmetic (>>1 for halving) to keep the compiled WAT type-clean.
  // f64 division creates an i32/f64 mismatch with libraryMultiplier when merged.
  const area: i32 = (base * height) >> 1;
  return area * libraryMultiplier;
}

// Void output function: the string "Library Version: v1.8.0-core" lives in THIS
// module's data section at offset 0 (relative to the library).  wasmmerge must
// shift the i32.const pointer inside this function body by mainModule.dataOffset
// so the merged binary reads from the correct relocated address.
/** @export */
export function logLibraryVersion(): void {
  console.log("Library Version: v1.8.0-core");
}
