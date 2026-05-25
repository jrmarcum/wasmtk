type i32 = number;

export function testRestSplitting(): void {
  console.log("--- Test 1: Array Rest Splitting ---");

  const source: i32[] = [100, 200, 300, 400];

  // Array destructuring with rest syntax
  const [alpha, beta, ...omega] = source;

  console.log("Alpha Element:", alpha);      // Expected: 100
  console.log("Beta Element:", beta);        // Expected: 200
  console.log("Rest Array Length:", omega.length); // Expected: 2
  console.log("Rest Index 0:", omega[0]);    // Expected: 300
  console.log("Rest Index 1:", omega[1]);    // Expected: 400
}

testRestSplitting();