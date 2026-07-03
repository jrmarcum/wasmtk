type i32 = number;

// Module-level state accessed by the transform function — avoids closure capture,
// so addOffset can be passed as a bare table-index funcref to mapArray.
const gOffset: i32 = 5;

function addOffset(val: i32): i32 {
  return val + gOffset;
}

// Concrete mapArray — replaces generic mapArray<T,U> + Transformer<T,U>.
// Accepts fn as a funcref (table index) via the funcTypeVars call_indirect path.
function mapArray(arr: i32[], fn: (v: i32) => i32): i32[] {
  const result: i32[] = [];
  for (let i = 0; i < arr.length; i++) {
    result.push(fn(arr[i]));
  }
  return result;
}

export function testGenericInterfacePipeline(): void {
  console.log("--- Test 2: Generic Interface Pipeline ---");

  const numbers: i32[] = [1, 2, 3];

  const output = mapArray(numbers, addOffset);
  console.log("Mapped Array Length:", output.length); // Expected: 3
  console.log("First Element:", output[0]);           // Expected: 6
  console.log("Third Element:", output[2]);           // Expected: 8
}

testGenericInterfacePipeline();
