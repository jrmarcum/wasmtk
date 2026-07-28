type i32 = number;
type f64 = number;

const enum StorageFlags {
  None = 0,
  Read = 1 << 0,  // 1
  Write = 1 << 1, // 2
  Admin = Read | Write // 3
}

export function testPhase22Prep(): void {
  console.log("--- Pre-Phase 23: Enum Folding & Casts ---");

  // Inline enum bit-masking
  const mask: i32 = StorageFlags.Admin;
  const isWriteAllowed = (mask & StorageFlags.Write) === StorageFlags.Write;

  // Exponentiation operator with numeric cast
  const baseVal: i32 = 2;
  const expVal: f64 = (baseVal ** 3) as f64; // 2 ** 3 = 8.0

  console.log("Admin Mask:", mask);                     // Expected: 3
  console.log("Write Allowed:", isWriteAllowed ? 1 : 0); // Expected: 1
  console.log("Exponent Cast:", expVal);                // Expected: 8
}

testPhase22Prep();
