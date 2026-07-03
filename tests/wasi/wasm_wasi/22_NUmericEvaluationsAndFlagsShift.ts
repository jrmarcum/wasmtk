type i32 = number;

enum PermissionFlags {
  None = 0,
  Read = 1 << 0,  // 1
  Write = 1 << 1, // 2
  Execute = 1 << 2, // 4
  Admin = Write | Execute, // 2 | 4 = 6
  MaxBits                 // Auto-increments from previous: 7
}

export function testNumericEnums(): void {
  console.log("--- Test 1: Numeric Enum Bit Optimization ---");

  const userPerm: i32 = PermissionFlags.Admin;
  const targetBit: i32 = PermissionFlags.Execute;

  // Mask check matching common bit-packing compiler scenarios
  const hasAccess = (userPerm & targetBit) === targetBit;

  console.log("Admin Flag Literal:", PermissionFlags.Admin);      // Expected: 6
  console.log("MaxBits Auto Literal:", PermissionFlags.MaxBits);   // Expected: 7
  console.log("Bitwise Mask Verification:", hasAccess ? 1 : 0); // Expected: 1
}

testNumericEnums();