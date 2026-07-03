// Regression — else / else-if chains that follow a SINGLE-LINE `if` must not be dropped.
// Both the brace-less form (`if (c) s; else if (c2) s2; else sN;`) and the single-line-braced form
// (`if (c) { … } else if (c2) { … }`, each branch on its own line) previously silently dropped
// every branch after the first (the if-handler only recognised a few braced multi-line else forms).
// NOTE: `deno fmt` de-braces single-statement bodies, so the single-line-BRACED form is exercised
// with non-trivial bodies (a nested `if`) that fmt preserves inline.
type i32 = number;

// Brace-less else-if chain after a single-line if.
function braceless(n: i32): i32 {
  let r: i32 = 0;
  if (n === 1) r = 10;
  else if (n === 2) r = 20;
  else if (n === 3) r = 30;
  else r = 99;
  return r;
}

// Single-line-braced else-if chain (bodies are nested ifs so fmt keeps them inline-braced).
function braced(n: i32): i32 {
  let r: i32 = 0;
  if (n === 1) { if (n > 0) r = 10; }
  else if (n === 2) { if (n > 0) r = 20; }
  else if (n > 0) r = 99;
  return r;
}

// Single-line if + a multi-line braced else (handled by the existing machinery — must still work).
function multilineElse(n: i32): i32 {
  let r: i32 = 0;
  if (n === 1) r = 10;
  else {
    r = 20;
    r = r + 5;
  }
  return r;
}

// Mixed chain: brace-less if, single-line-braced else-if, brace-less else.
function mixed(n: i32): i32 {
  let found: i32 = 0;
  if (n === 1) found = 1;
  else if (n === 2) { if (n > 0) found = 2; }
  else found = 9;
  return found;
}

console.log("braceless:", braceless(1), braceless(2));
console.log("braceless:", braceless(3), braceless(7));
console.log("braced:", braced(1), braced(2), braced(7));
console.log("multilineElse:", multilineElse(1), multilineElse(2));
console.log("mixed:", mixed(1), mixed(2), mixed(7));
