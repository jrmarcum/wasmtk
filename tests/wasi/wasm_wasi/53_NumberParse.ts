// Phase 53 — Number.parseInt(s, radix) / Number.parseFloat(s) + bare parseInt / parseFloat.
// String -> number (f64). parseInt stops at the first char invalid for the radix (default 10;
// a 0x/0X prefix is honored when radix is 16 or omitted). parseFloat reads an optional sign,
// integer/fraction, and e-exponent. No valid leading digits -> NaN. Exercised via the
// assign-then-log value path (direct console.log(parseInt(...)) routes through a local).
type i32 = number;
type f64 = number;

function main(): void {
  const a: f64 = Number.parseInt("42", 10);
  console.log("a:", a); // 42

  const b: f64 = Number.parseInt("ff", 16);
  console.log("b:", b); // 255

  const c: f64 = Number.parseInt("0x1A", 16);
  console.log("c:", c); // 26

  const d: f64 = Number.parseInt("0xFF");
  console.log("d:", d); // 255 (auto-hex when radix omitted)

  const e: f64 = Number.parseInt("  -17");
  console.log("e:", e); // -17 (leading whitespace + sign, default radix 10)

  const f: f64 = Number.parseInt("100px", 10);
  console.log("f:", f); // 100 (stops at first invalid char)

  const g: f64 = Number.parseFloat("3.14");
  console.log("g:", g); // 3.14

  const h: f64 = Number.parseFloat("2.5e3");
  console.log("h:", h); // 2500

  const i: f64 = Number.parseFloat("-0.25");
  console.log("i:", i); // -0.25

  const j: f64 = parseInt("255", 10);
  console.log("j:", j); // 255 (bare parseInt)

  const k: f64 = parseFloat("1.5");
  console.log("k:", k); // 1.5 (bare parseFloat)

  // No annotation: inferInitType resolves parseInt(...) to number (f64).
  const m = parseInt("7", 10);
  console.log("m:", m); // 7
}

main();
