type i32 = number;
type f64 = number;

// Tuple containing a nullable primitive and a nullable struct pointer
type NullableTuple = [i32 | null, f64];

function getTupleValue(flag: boolean): NullableTuple | null {
  if (!flag) {
    return null; // Sets $__nullable_ret_flag to 0
  }
  // Allocates tuple struct, setting internal field flags
  return [100, 3.14159];
}

export function testPhase24Post(): void {
  console.log("--- Post-Phase 23: Nullable Tuples & Flags ---");

  // Call returning null
  const nullResult = getTupleValue(false);
  console.log("Null Check:", nullResult === null ? 1 : 0); // Expected: 1

  // Call returning valid tuple pointer
  const validResult = getTupleValue(true);
  if (validResult !== null) {
    const [val, ratio] = validResult;
    console.log("Extracted Int:", val ?? -1); // Nullish coalescing fallback (Phase 25)
    console.log("Extracted Float:", ratio);
  }
}

testPhase24Post();
