function add(a: number, b: number): number {return a + b;}
function multiply(a: number, b: number): number {return a * b;}
function divide(a: number, b: number): number { return a / b; }
function subtract(a: number, b: number): number { return a - b; }

function main(): void {
  console.log(`Sum: ${add(5, 6)}`);
  console.log(`Product: ${multiply(4, 5)}`);
  console.log(`Quotient: ${divide(30, 2)}`);
  console.log(`Difference: ${subtract(20, 3)}`);
}
main();