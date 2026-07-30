// Phase 31 — TypedArray literal initializer: `new Float64Array([...])` must allocate
// the header and copy the float literal bytes; .length vs .byteLength (8 bytes/element).
type f64 = number;

export function testTypedArrayInitializer(): void {
  console.log("--- Test 2: TypedArray Initializer ---");

  // Allocates header + copies literal float bytes
  const floats = new Float64Array([10.5, 20.25, 30.75]);

  console.log("Float64 Length:", floats.length);         // Expected: 3
  console.log("Float64 ByteLength:", floats.byteLength); // Expected: 24 (3 * 8 bytes)
  console.log("Float64 Index 0:", floats[0]);            // Expected: 10.5
  console.log("Float64 Index 2:", floats[2]);            // Expected: 30.75
}

testTypedArrayInitializer();
