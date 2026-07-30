type i32 = number;
type f64 = number;

type ValueContainer =
  | { type: "intVal"; val: i32 }
  | { type: "floatVal"; val: f64 };

function extractAsFloat(container: ValueContainer): f64 {
  if (container.type === "intVal") {
    // Explicit cast of narrowed variant field
    return container.val as f64;
  } else if (container.type === "floatVal") {
    return container.val;
  }
  return 0.0;
}

export function testElseIfNarrowing(): void {
  console.log("--- Test 3: Chained else if Narrowing ---");

  const v1: ValueContainer = { type: "intVal", val: 100 };
  const v2: ValueContainer = { type: "floatVal", val: 25.5 };

  console.log("Int Extracted as Float:", extractAsFloat(v1)); // Expected: 100
  console.log("Float Extracted as Float:", extractAsFloat(v2)); // Expected: 25.5
}

testElseIfNarrowing();
