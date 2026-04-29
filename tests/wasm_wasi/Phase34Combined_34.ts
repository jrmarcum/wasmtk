// Phase 34 — Combined: type predicates with DU types and interface inheritance
type i32 = number;
type f64 = number;

// ── Discriminated union with type predicates ────────────────────────────────
type Expr =
  | { tag: "num"; value: f64 }
  | { tag: "add"; left: f64; right: f64 };

function isNum(e: Expr): e is Expr {
  return e.tag === "num";
}

function isAdd(e: Expr): e is Expr {
  return e.tag === "add";
}

function evalExpr(e: Expr): f64 {
  if (isNum(e)) {
    return e.value;
  }
  if (isAdd(e)) {
    return e.left + e.right;
  }
  return 0.0;
}

// ── Interface inheritance with type predicates ──────────────────────────────
interface Node {
  kind: i32;
  depth: i32;
}

interface LeafNode extends Node {
  data: i32;
}

interface BranchNode extends Node {
  children: i32;
}

function isLeaf(n: Node): n is LeafNode {
  return n.kind === 0;
}

function isBranch(n: Node): n is BranchNode {
  return n.kind === 1;
}

function describeNode(n: Node): void {
  if (isLeaf(n)) {
    console.log("leaf data:", n.data);
    console.log("leaf depth:", n.depth);
  } else if (isBranch(n)) {
    console.log("branch children:", n.children);
  } else {
    console.log("unknown node");
  }
}

function main(): void {
  // DU type predicates
  const numExpr: Expr = { tag: "num", value: 42.0 };
  const addExpr: Expr = { tag: "add", left: 10.0, right: 32.0 };

  console.log(isNum(numExpr));  // true
  console.log(isAdd(numExpr));  // false
  console.log(evalExpr(numExpr)); // 42
  console.log(evalExpr(addExpr)); // 42

  // Interface inheritance predicates
  const leaf: LeafNode   = { kind: 0, depth: 3, data: 99 };
  const branch: BranchNode = { kind: 1, depth: 1, children: 4 };
  const node: Node         = { kind: 2, depth: 0 };

  console.log(isLeaf(leaf));    // true
  console.log(isBranch(leaf));  // false
  console.log(isBranch(branch)); // true

  describeNode(leaf);   // leaf data: 99 / leaf depth: 3
  describeNode(branch); // branch children: 4
  describeNode(node);   // unknown node
}

main();
