type i32 = number;
type f64 = number;

interface StatusPayload {
  kind: "status"; // Tag index 0
  code: i32;
}

interface DataPayload {
  kind: "data";   // Tag index 1
  val1: f64;
  val2: f64;
  id: i32;
}

type NetworkEvent = StatusPayload | DataPayload;

export function processEvent(event: NetworkEvent): f64 {
  // Verifies type predicate narrowing on literal string fields
  if (event.kind === "status") {
    // Fixed: Using type assertion instead of an inline function call
    return event.code as f64;
  } else {
    // If 'data', fields sit at offsets after the initial 4-byte variant tag.
    // Largest variant requires 24 bytes (f64 + f64 + i32) + 4-byte tag = 28 bytes total.
    return event.val1 + event.val2 + (event.id as f64);
  }
}

export function testUnionAlignment(): void {
  console.log("--- Test 1: Union Footprint Alignment ---");

  // Allocate small variant (should allocate full 28-byte chunk internally to match max)
  const ev1: NetworkEvent = { kind: "status", code: 200 };
  console.log("Status Code Extracted:", processEvent(ev1)); // Expected: 200

  // Allocate large variant 
  const ev2: NetworkEvent = { kind: "data", val1: 10.5, val2: 20.5, id: 50 };
  console.log("Data Sum Extracted:", processEvent(ev2));   // Expected: 10.5 + 20.5 + 50 = 81
}

testUnionAlignment();