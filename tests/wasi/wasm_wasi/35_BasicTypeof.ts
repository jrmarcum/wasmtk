// Phase 35 — typeof: basic comparisons, assignment, and console.log
type i32 = number;
type f64 = number;

function main(): void {
  const n: i32 = 42;
  const d: f64 = 3.14;
  const s: string = "hello";
  const flag: bool = true;

  // typeof === comparisons: compile-time constants
  if (typeof n === "number") {
    console.log("n is number");    // n is number
  }
  if (typeof d === "number") {
    console.log("d is number");    // d is number
  }
  if (typeof s === "string") {
    console.log("s is string");    // s is string
  }
  if (typeof flag === "boolean") {
    console.log("flag is boolean"); // flag is boolean
  }

  // typeof !== comparisons (false branches — should print)
  if (typeof n !== "string") {
    console.log("n is not string"); // n is not string
  }
  if (typeof s !== "number") {
    console.log("s is not number"); // s is not number
  }

  // typeof as string value — stored in a string variable
  const tn: string = typeof n;
  const ts: string = typeof s;
  const tf: string = typeof flag;
  console.log("typeof n:", tn);    // typeof n: number
  console.log("typeof s:", ts);    // typeof s: string
  console.log("typeof flag:", tf); // typeof flag: boolean
}

main();
