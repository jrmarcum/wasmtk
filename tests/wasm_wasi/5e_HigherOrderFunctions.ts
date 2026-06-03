type i32 = number;
// A function that accepts a callback
function applyLogic(val: i32, callback: (n: i32) => i32): i32 {
  return callback(val);
}

(function testCallbacks(): void {
  // Passing an anonymous arrow function directly
  const result = applyLogic(10, (n) => n * n);
  console.log(result); // 100

  // Passing a pre-defined arrow
  const increment = (n: i32): i32 => n + 1;
  console.log(applyLogic(10, increment)); // 11
})();