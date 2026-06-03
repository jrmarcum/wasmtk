type i32 = number;
function compose(initial: i32) {
  const inner = (x: i32) => x + initial;
  return (y: i32) => inner(y) * 2; // Captures a closure pointer
}

console.log(compose(5)(10)); // Output: 30