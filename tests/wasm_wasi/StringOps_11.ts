// Phase 11 — String Operations
// Tests: indexOf, includes, slice, concat (+), String(n), n.toString()

const greeting: string = "Hello, World!";

// indexOf: found and not found
const idx: i32 = greeting.indexOf("World");
console.log(idx);           // 7

const missing: i32 = greeting.indexOf("xyz");
console.log(missing);       // -1

// includes
const hasHello: bool = greeting.includes("Hello");
console.log(hasHello);      // 1  (true)

const hasXyz: bool = greeting.includes("xyz");
console.log(hasXyz);        // 0  (false)

// slice
const sub: string = greeting.slice(7, 12);
console.log(sub);           // World

// slice — empty result when start >= end
const empty: string = greeting.slice(5, 5);
console.log(empty.length);  // 0

// concat (str + str)
const first: string = "Hello";
const second: string = ", ";
const third: string = "Deno!";
const full: string = first + second + third;
console.log(full);          // Hello, Deno!

// concat with literal
const prefixed: string = "Result: " + first;
console.log(prefixed);      // Result: Hello

// String(n) — integer to string then concat
const n: i32 = 42;
const ns: string = String(n);
console.log(ns);            // 42

// n.toString() — float to string
const x: f64 = 3.14;
const xs: string = x.toString();
console.log(xs);            // 3.14

// indexOf on a sliced string
const target: string = "abcdef";
const sliced: string = target.slice(2, 6);   // "cdef"
const found: i32 = sliced.indexOf("de");
console.log(found);         // 1  ("de" starts at index 1 in "cdef")

// includes on a concatenated result
const cat: string = "foo" + "bar";
const hasFoo: bool = cat.includes("foo");
console.log(hasFoo);        // 1
