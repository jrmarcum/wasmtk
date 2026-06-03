type i32 = number;
function compose(initial: i32) {
  const inner = (x: i32) => x + initial; // Closure A
  return (y: i32) => inner(y) * 2;        // Closure B (captures Closure A)
}

console.log(compose(5)(10)); // Output: 30