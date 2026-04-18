function fib(num) {
  let a = 0;
  let b = 1;
  let temp = 0;
  while (num > 0) {
    temp = a;
    a = a + b;
    b = temp;
    num -= 1;
  }
  return a;
}
console.log(`Fibonacci result is: ${fib(10)}`);
export {
  fib
};
