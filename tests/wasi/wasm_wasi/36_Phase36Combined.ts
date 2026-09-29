// Phase 36 — Combined: generic + non-generic conditional types + function signatures
type i32 = number;
type f64 = number;

// Generic: if T is i32 → f64; otherwise → i32
type AsFloat<T> = T extends i32 ? f64 : i32;

// Non-generic: f64 extends number → true → i32
type AlwaysI32 = f64 extends number ? i32 : string;

// Non-generic false branch: string extends i32 → false → f64
type AlwaysF64 = string extends i32 ? i32 : f64;

function area(w: AsFloat<i32>, h: AsFloat<i32>): AsFloat<i32> {   // f64, f64 → f64
  return w * h;
}

function count(items: AlwaysI32): void {   // i32
  console.log("items:", items);
}

function ratio(x: AlwaysF64): void {   // f64
  console.log("ratio:", x);
}

function main(): void {
  const w: AsFloat<i32> = 2.5;   // f64
  const h: AsFloat<i32> = 4.0;   // f64
  const n: AsFloat<f64> = 7;     // i32
  const m: AlwaysI32    = 100;   // i32
  const r: AlwaysF64    = 1.5;   // f64

  console.log("w:", w);   // w: 2.5
  console.log("h:", h);   // h: 4
  console.log("n:", n);   // n: 7
  console.log("m:", m);   // m: 100
  console.log("r:", r);   // r: 1.5

  const result: AsFloat<i32> = area(w, h);
  console.log("area:", result);   // area: 10

  count(m);      // items: 100
  ratio(r);      // ratio: 1.5
}

main();
