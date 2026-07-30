// Regression: `string`-typed namespace members used to be broken. `export const NAME: string`
// printed `0` (silently wrong) and a string-RETURNING namespace function failed to instantiate,
// because each qualified use site was resolved ad hoc (a numeric-constant branch, a dot-call
// branch) and neither understood the string ptr/len ABI. `expandNamespaces` now rewrites
// `Ns.member` → `Ns_member`, making a namespace member an ORDINARY top-level symbol that every
// existing path handles. See design-decisions.md § "Namespace member references are rewritten".

type i32 = number;
type f64 = number;

interface Box {
  NAME: string; // deliberately shares a name with the namespace member
  LIMIT: i32;
}

namespace Cfg {
  export const NAME: string = "cfg";
  export const LIMIT: i32 = 7;
  export const RATE: f64 = 1.5;

  export function greet(who: string): string {
    return "hi " + who;
  }

  export function twice(v: i32): i32 {
    return v * LIMIT; // unqualified sibling const
  }
}

export function testNamespaceStringMembers(): void {
  console.log("--- Namespace string members ---");

  // Constants of every scalar kind
  console.log("string const:", Cfg.NAME); // cfg   (was 0)
  console.log("i32 const:", Cfg.LIMIT); // 7
  console.log("f64 const:", Cfg.RATE); // 1.5

  // A string-RETURNING namespace function, in every position
  console.log("string fn inline:", Cfg.greet("there")); // hi there  (failed to instantiate)
  const s: string = Cfg.greet("x");
  console.log("string fn assigned:", s); // hi x
  console.log("string const concat:", "[" + Cfg.NAME + "]"); // [cfg]
  console.log("string const compare:", Cfg.NAME === "cfg" ? 1 : 0); // 1

  console.log("i32 fn:", Cfg.twice(3)); // 21

  // A struct FIELD sharing a member name must NOT be rewritten
  const b: Box = { NAME: "field", LIMIT: 99 };
  console.log("struct field NAME:", b.NAME); // field
  console.log("struct field LIMIT:", b.LIMIT); // 99

  // A member name inside a string LITERAL must survive verbatim
  console.log("literal:", "Cfg.NAME stays as written"); // Cfg.NAME stays as written
}

testNamespaceStringMembers();
