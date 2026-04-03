export function fib(num:number): number {
  var a: number = 0;
  var b: number = 1;
  var temp: number = 0;

  while (num > 0) {
    temp = a;
    a = a + b;
    b = temp;
    num -= 1;
  }
  return a
}

(function main():void{
  console.log(`Fibonacci result is: ${fib(10)}`);
}).call(this);