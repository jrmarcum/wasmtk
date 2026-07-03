// Test Exported Const Enum
export const enum Status {
  Pending,   // 0
  Active,    // 1
  Closed = 5,
  Archived   // 6 (auto-increment from 5)
}

// Test Standard Enum (if your parser handles both)
enum Color {
  Red = 10,
  Green = 20,
  Blue = 30
}

export function testEnums(): void {
  const currentStatus = Status.Archived;
  
  if (currentStatus === 6) {
    console.log(Status.Active); // Should emit (i32.const 1)
  }

  const myColor = Color.Green;
  console.log(myColor); // Should emit (i32.const 20)
}

testEnums();