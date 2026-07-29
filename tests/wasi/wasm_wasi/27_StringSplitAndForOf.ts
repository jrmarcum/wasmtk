type i32 = number;

export function testStringSplitAndForOf(): void {
  console.log("--- Test 1: String Split & String Array for...of ---");

  const csvData: string = "alpha,beta,gamma,delta";
  const parts: string[] = csvData.split(",");

  console.log("Split Array Length:", parts.length); // Expected: 4

  let uppercaseConcat: string = "";
  for (const part of parts) {
    console.log("Item:", part);
    uppercaseConcat = uppercaseConcat + part.toUpperCase() + ":";
  }

  console.log("Formatted Output:", uppercaseConcat);
  // Expected: ALPHA:BETA:GAMMA:DELTA:
}

testStringSplitAndForOf();
