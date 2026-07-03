// Phase 51.3 — Nested destructuring: const { a: { b } } = obj and nested in params.
type i32 = number;
type f64 = number;

interface Inner {
  b: i32;
  c: i32;
}

interface Outer {
  a: Inner;
  d: i32;
}

interface Deep {
  inner: Outer;
  tag: i32;
}

// Nested destructuring in a function parameter.
function sumNested({ a: { b, c }, d }: Outer): i32 {
  return b + c + d;
}

function main(): void {
  // One level of nesting.
  const o: Outer = { a: { b: 5, c: 7 }, d: 9 };
  const { a: { b, c }, d } = o;
  console.log("b:", b); // 5
  console.log("c:", c); // 7
  console.log("d:", d); // 9

  // Renamed bindings inside a nested pattern.
  const { a: { b: bb, c: cc } } = o;
  console.log("bb:", bb); // 5
  console.log("cc:", cc); // 7

  // Two levels deep.
  const deep: Deep = { inner: { a: { b: 1, c: 2 }, d: 3 }, tag: 99 };
  const { inner: { a: { b: db, c: dc }, d: dd }, tag } = deep;
  console.log("db:", db);   // 1
  console.log("dc:", dc);   // 2
  console.log("dd:", dd);   // 3
  console.log("tag:", tag); // 99

  // Nested destructuring in a function parameter.
  const src: Outer = { a: { b: 10, c: 20 }, d: 30 };
  console.log("sumNested:", sumNested(src)); // 60
}

main();
