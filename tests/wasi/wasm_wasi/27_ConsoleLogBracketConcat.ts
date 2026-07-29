// Regression: console_log.ts's findTopLevelOp counted ()/[] for depth but did NOT skip string
// literals, so a closing `]` or `)` INSIDE a literal drove depth above 0 and hid the top-level
// `+`. The whole concat then fell through to the numeric path and printed `0`.
// `"{" + w + "}"` happened to work only because braces are not counted at all.
// See design-decisions.md § "Bracket/paren/operator scanners MUST skip string literals".

type i32 = number;

export function testBracketConcat(): void {
  const w: string = "V";

  console.log("plain:", "a" + w + "b"); // aVb  (worked before)
  console.log("bracket:", "[" + w + "]"); // [V]  (was 0)
  console.log("paren:", "(" + w + ")"); // (V)  (was 0)
  console.log("brace:", "{" + w + "}"); // {V}  (worked before)
  console.log("open only:", "[" + w); // [V   (worked before)
  console.log("close only:", w + "]"); // V]   (was 0)
  console.log("nested:", "[(" + w + ")]"); // [(V)]

  // The same shape via a join()-derived string (Phase 28 join as a string VALUE)
  const nums: i32[] = [7, 8];
  console.log("join in brackets:", "[" + nums.join(",") + "]"); // [7,8]

  // A literal that is ONLY brackets must still concatenate
  console.log("literal brackets:", w + "[]"); // V[]
}

testBracketConcat();
