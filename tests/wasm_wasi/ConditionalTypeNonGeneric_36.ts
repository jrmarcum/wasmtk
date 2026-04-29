// Phase 36 — Non-generic conditional types (evaluated at declaration time)
type i32 = number;
type f64 = number;

// Evaluated at compile time — no type parameter:
type TrueResult  = i32 extends i32    ? string : f64;   // i32 extends i32    → true  → string
type FalseResult = string extends i32 ? i32    : f64;   // string extends i32 → false → f64
type NumResult   = f64 extends number ? i32    : string; // f64 extends number → true  → i32

function printStr(label: string, s: TrueResult): void {   // TrueResult = string
  console.log(label, s);
}

function main(): void {
  const a: TrueResult  = "hello";   // string
  const b: FalseResult = 9.99;      // f64
  const c: NumResult   = 42;        // i32

  console.log("a:", a);   // a: hello
  console.log("b:", b);   // b: 9.99
  console.log("c:", c);   // c: 42

  printStr("label:", "wasic");   // label: wasic
}

main();
