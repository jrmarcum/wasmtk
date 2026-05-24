// MainApplication_Wasic_18.ts
type i32 = number;

// Declare the blueprint of the library to satisfy wasic's closed-world parser
declare const MathLib: {
  computeScaledArea: (b: i32, h: i32) => i32;
  getLibraryVersion: () => string;
};

export function _start(): void {
  console.log("--- Test 1: Static Function Linkage ---");
  // This symbol call maps to an external import that wasmmerge must resolve locally
  const areaResult = MathLib.computeScaledArea(10, 4); 
  console.log("Scaled Area Result:", areaResult); // Expected: ((10 * 4) / 2) * 3 = 60

  console.log("--- Test 2: Shifted Data Segment Pointers ---");
  const versionStr = MathLib.getLibraryVersion();
  console.log("Library Version:", versionStr); // Expected: v1.8.0-core
}