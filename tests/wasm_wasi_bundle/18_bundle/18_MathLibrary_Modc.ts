// MathLibrary_Modc_18.ts
type i32 = number;

// Internal library-scoped state to test global index shifting
const libraryMultiplier: i32 = 3; 

/** @export */
export function computeScaledArea(base: i32, height: i32): i32 {
  const rawArea = (base * height) / 2;
  return rawArea * libraryMultiplier;
}

/** @export */
export function getLibraryVersion(): string {
  return "v1.8.0-core"; // Tests data segment relocation and string pointer offsets
}