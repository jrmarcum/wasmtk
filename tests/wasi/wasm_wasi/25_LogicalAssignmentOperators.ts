type i32 = number;

let globalNullable: i32 | null = null;
let globalCounter: i32 = 10;

export function testLogicalAssignments(): void {
  console.log("--- Test 2: Logical Assignment Operators ---");

  // Nullish Assignment (??=)
  let localNullable: i32 | null = null;
  localNullable ??= 55;
  console.log("Local ??= on null:", localNullable); // Expected: 55

  localNullable ??= 100;
  console.log("Local ??= on non-null:", localNullable); // Expected: 55

  // Module Globals Nullish Assignment
  globalNullable ??= 77;
  console.log("Global ??= on null:", globalNullable); // Expected: 77

  // Logical OR Assignment (||=)
  let zeroLocal: i32 = 0;
  zeroLocal ||= 300;
  console.log("Local ||= on zero:", zeroLocal); // Expected: 300

  // Logical AND Assignment (&&=)
  globalCounter &&= 20;
  console.log("Global &&= on truthy:", globalCounter); // Expected: 20
}

testLogicalAssignments();
