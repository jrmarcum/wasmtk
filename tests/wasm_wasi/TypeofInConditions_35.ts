// Phase 35 — typeof: use in console.log, conditions, and nested scopes
type i32 = number;
type f64 = number;

function checkAndLog(n: i32, s: string, b: bool): void {
  console.log("n type:", typeof n);    // n type: number
  console.log("s type:", typeof s);    // s type: string
  console.log("b type:", typeof b);    // b type: boolean

  // typeof in if conditions inside a function
  if (typeof n === "number") {
    console.log("n confirmed number"); // n confirmed number
  }
  if (typeof s === "string") {
    console.log("s confirmed string"); // s confirmed string
  }
}

function storeTypes(x: i32, y: f64): void {
  const tx: string = typeof x;
  const ty: string = typeof y;
  console.log("x type stored:", tx);  // x type stored: number
  console.log("y type stored:", ty);  // y type stored: number
}

function main(): void {
  const x: i32 = 10;
  const msg: string = "test";
  const active: bool = false;
  const pi: f64 = 3.14;

  // Direct typeof in console.log
  console.log(typeof x);       // number
  console.log(typeof msg);     // string
  console.log(typeof active);  // boolean
  console.log(typeof pi);      // number

  // typeof in function call
  checkAndLog(5, "hello", true);

  // Store typeof result and use it
  storeTypes(7, 2.718);

  // typeof with else
  const val: i32 = 99;
  if (typeof val === "string") {
    console.log("wrong");        // should not print
  } else {
    console.log("val is not string"); // val is not string
  }
}

main();
