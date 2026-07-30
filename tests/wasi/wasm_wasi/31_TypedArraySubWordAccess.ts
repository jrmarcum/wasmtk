// Phase 31 — TypedArray sub-word access: Uint8Array/Int16Array element width,
// .length vs .byteLength, and sign-extension on a negative Int16 element.
type i32 = number;

export function testTypedArrayAccess(): void {
  console.log("--- Test 1: TypedArray Sub-Word Access ---");

  const bytes = new Uint8Array(4);
  bytes[0] = 255;
  bytes[1] = 128;
  bytes[2] = 64;
  bytes[3] = 32;

  console.log("Uint8 Length:", bytes.length);          // Expected: 4
  console.log("Uint8 ByteLength:", bytes.byteLength);  // Expected: 4
  console.log("Uint8 Index 0:", bytes[0]);             // Expected: 255
  console.log("Uint8 Index 2:", bytes[2]);             // Expected: 64

  const shorts = new Int16Array(2);
  shorts[0] = 32000;
  shorts[1] = -16000;

  console.log("Int16 ByteLength:", shorts.byteLength); // Expected: 4 (2 elements * 2 bytes)
  console.log("Int16 Index 1:", shorts[1]);            // Expected: -16000
}

testTypedArrayAccess();
