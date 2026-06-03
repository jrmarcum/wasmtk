// complex.ts

export function add(a: number, b: number): number {
  return a + b;
}

export function multiply(a: number, b: number): number {
  return a * b;
}

(function main(){
  console.log(add(2,5));
  console.log(multiply(2,5));
 })()