type i32 = number;
function createAdder(x: i32) {
  // x must "escape" to the heap because this function returns
  return (y: i32) => x + y;
}

export function _start(): void {
  const addFive: (y: i32) => i32 = createAdder(5);
  const result: i32 = addFive(10);
  console.log(result);
}

_start();