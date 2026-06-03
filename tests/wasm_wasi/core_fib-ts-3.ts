export function fib(num:number): number {
  let a: number = 0;
  let b: number = 1;
  let temp: number = 0;

  while (num > 0) {
    temp = a;
    a = a + b;
    b = temp;
    num -= 1;
  }
  return a
}

if (import.meta.main){
  console.log(`Fibonacci result is: ${fib(10)}`);
}
