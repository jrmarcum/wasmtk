type i32 = number;
function createAdder(x: i32) {
  // x must "escape" to the heap because this function returns
  return (y: i32) => x + y;
}

export function _start(): void {
  const addFive = createAdder(5);
  const result = addFive(10);
  console.log(result);
}

_start();