// Regression (2026-09-28): string literals with escaped quotes were matched with `"([^"]*)"`, which
// stops at the first `\"`. A string ARGUMENT to a call inside console.log(...) then became "" (the
// 2026-05-31 JSON-work residual), and a string ENUM member fell to the numeric branch.
type i32 = number;

enum Quote {
  Plain = "plain",
  Escaped = "say \"hi\"",
  Single = 'it\'s',
}

function len(s: string): i32 {
  return s.length;
}

function echo(s: string): string {
  return "[" + s + "]";
}

console.log(len("plain"), len("a\"b"), len('it\'s'));
console.log(echo("say \"hi\""));
const a: string = Quote.Escaped;
const b: string = Quote.Single;
console.log(a);
console.log(b, Quote.Plain);
