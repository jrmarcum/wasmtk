// Phase 51 combined: instanceof in an inheritance hierarchy — runtime tag check, narrowing in
// an if/else-if chain, instanceof in a boolean variable, instanceof inside a logical expression,
// and instanceof of a base-typed array element.

type i32 = number;

const guard: i32[] = [0];

function check(cond: i32): void {
  if (cond === 0) {
    const x: i32 = guard[5000000];
    console.log(x);
  }
}

class Node {
  key: i32;
  constructor(k: i32) {
    this.key = k;
  }
}

class Leaf extends Node {
  value: i32;
  constructor(k: i32, v: i32) {
    super(k);
    this.value = v;
  }
}

class Branch extends Node {
  count: i32;
  constructor(k: i32, c: i32) {
    super(k);
    this.count = c;
  }
}

// else-if chain narrowing: each branch narrows `n` and reads a subclass-only field.
function weight(n: Node): i32 {
  if (n instanceof Leaf) {
    return n.value;
  } else if (n instanceof Branch) {
    return n.count * 10;
  } else {
    return n.key;
  }
}

function main(): void {
  const leaf: Node = new Leaf(1, 42);
  const branch: Node = new Branch(2, 5);
  const plain: Node = new Node(99);

  check(weight(leaf) === 42 ? 1 : 0);
  check(weight(branch) === 50 ? 1 : 0);
  check(weight(plain) === 99 ? 1 : 0);

  // instanceof in a boolean variable.
  const leafIsNode: boolean = leaf instanceof Node;
  check(leafIsNode ? 1 : 0);

  // instanceof combined with && (short-circuit) and the narrowed field read.
  if (leaf instanceof Leaf && leaf.value === 42) {
    check(1);
  } else {
    check(0);
  }

  // Base-typed array of mixed concrete subclasses — instanceof on an element.
  // (Built via push: array literals of `new` instances are not constructed — pre-existing.)
  const nodes: Node[] = [];
  nodes.push(new Leaf(3, 7));
  nodes.push(new Branch(4, 2));
  nodes.push(new Leaf(5, 8));
  let leafCount: i32 = 0;
  let k: i32 = 0;
  while (k < 3) {
    if (nodes[k] instanceof Leaf) {
      leafCount = leafCount + 1;
    }
    k = k + 1;
  }
  check(leafCount === 2 ? 1 : 0);

  console.log("leaf is Node:", leaf instanceof Node);
  console.log("branch is Leaf:", branch instanceof Leaf);
  console.log("leaf count:", leafCount);
  console.log("phase 51 combined ok");
}

main();
