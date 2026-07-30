// Phase 31 — TypedArray .fill(value, start, end) with an exclusive end bound, and
// .set(src, offset) copying one TypedArray into another at an offset.
type i32 = number;

export function testTypedArrayFillAndSet(): void {
  console.log("--- Test 3: TypedArray .fill() and .set() ---");

  const buf = new Int32Array(5);
  buf.fill(42, 1, 4); // Fills indices 1, 2, 3 with 42

  console.log("Fill Index 0:", buf[0]); // Expected: 0
  console.log("Fill Index 2:", buf[2]); // Expected: 42
  console.log("Fill Index 4:", buf[4]); // Expected: 0

  const src = new Int32Array([100, 200]);
  buf.set(src, 3); // Copies src elements starting at index 3 of buf

  console.log("Set Index 3:", buf[3]); // Expected: 100
  console.log("Set Index 4:", buf[4]); // Expected: 200
}

testTypedArrayFillAndSet();
