// Regression: `expandNamespaces` renamed a namespace's exported declarations to `Ns_name` but left
// UNQUALIFIED references inside the namespace body pointing at the old bare name, so
// `return mass * GRAVITY` aborted with "Unsupported expression: GRAVITY". Existing Phase 30 tests
// declared namespace constants but never read one from inside a namespace function, so this went
// untested. See design-decisions.md § "Namespace member references are rewritten inside the body".

type i32 = number;

interface Holder {
  LIMIT: i32; // deliberately shares a name with the namespace member below
}

namespace Cfg {
  export const LIMIT: i32 = 5;
  export const STEP: i32 = 2;

  // bare reference to a sibling CONST
  export function scale(v: i32): i32 {
    return v * LIMIT;
  }

  // bare call to a sibling FUNCTION, plus another const reference
  export function scaleTwice(v: i32): i32 {
    return scale(v) + STEP;
  }

  // a member name inside a STRING LITERAL must NOT be rewritten
  export function describe(): i32 {
    const note: string = "LIMIT and STEP are just words here";
    return note.length;
  }
}

export function testNamespaceInternalRefs(): void {
  console.log("--- Namespace internal references ---");

  console.log("const via ns:", Cfg.LIMIT); // 5
  console.log("const ref inside fn:", Cfg.scale(3)); // 15
  console.log("sibling fn call:", Cfg.scaleTwice(3)); // 17
  console.log("literal untouched:", Cfg.describe()); // 34

  // A struct FIELD sharing the member name must not be rewritten either
  const h: Holder = { LIMIT: 99 };
  console.log("struct field:", h.LIMIT); // 99
}

testNamespaceInternalRefs();
