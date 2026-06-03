// Phase_5e_Upward.ts
type i32 = number;
function createMultiplier(x: i32) {
  // Returning the closure - x must persist on the heap
  return (y: i32) => x * y;
}

export function _start(): void {
  const triple = createMultiplier(3);
  const result = triple(10);
  console.log(result); // Expected: 30
}

_start();