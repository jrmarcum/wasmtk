type i32 = number;

export function testArrayJoin(): void {
  console.log("--- Test 3: Array join() ---");

  const values: i32[] = [10, 20, 30, 40];

  const defaultJoined: string = values.join(); // Default separator ","
  const customJoined: string = values.join(" - "); // Custom separator

  console.log("Default Join:", defaultJoined); // Expected: "10,20,30,40"
  console.log("Custom Join:", customJoined); // Expected: "10 - 20 - 30 - 40"
}

testArrayJoin();
