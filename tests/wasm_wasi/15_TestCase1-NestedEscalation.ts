type i32 = number;

let globalTrace: i32 = 0;

function levelThree(fail: i32): void {
  if (fail === 1) {
    throw new Error("Level 3 Failure"); // Phase 15 native exception
  }
}

function levelTwo(fail: i32): void {
  try {
    globalTrace += 10;
    levelThree(fail);
    globalTrace += 5;  // Skipped if failing
  } finally {
    globalTrace += 2;  // Must execute on both paths
  }
}

export function testNestedEscalation(fail: i32): i32 {
  globalTrace = 0;
  try {
    levelTwo(fail);
  } catch (e) {
    // Phase 15 catch blocks bind exception messages[cite: 25]
    console.log("Caught:", e.message); 
    return globalTrace;
  }
  return globalTrace;
}

// Execution block compatible with both TS runtimes and wasic _start[cite: 25]
console.log("--- Test 1: Success Path ---");
const score1 = testNestedEscalation(0);
console.log("Final Trace Score:", score1); // Expected: 17

console.log("--- Test 1: Failure Path ---");
const score2 = testNestedEscalation(1);
console.log("Final Trace Score:", score2); // Expected: 12