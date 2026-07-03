type i32 = number;

interface LeafNode { type: "leaf"; weight: i32; }
interface InternalNode { type: "internal"; branchCount: i32; active: i32; }

type TreeNode = LeafNode | InternalNode;

export function testUnionArrayOps(): void {
  console.log("--- Test 3: Polymorphic Union Array ---");

  // Array storing flat super-struct union elements
  const cluster: TreeNode[] = [];

  cluster.push({ type: "leaf", weight: 45 });
  cluster.push({ type: "internal", branchCount: 4, active: 1 });
  cluster.push({ type: "leaf", weight: 55 });

  // Update/Mutate element inline to completely swap its active variant type
  // This tests that writing a smaller variant over a larger one leaves correct trailing values
  cluster[1] = { type: "leaf", weight: 12 }; 

  let combinedWeight: i32 = 0;
  for (let i = 0; i < cluster.length; i++) {
    const node = cluster[i];
    if (node.type === "leaf") {
      combinedWeight += node.weight;
    } else {
      combinedWeight += node.branchCount; // Skipped since we overwrote index 1
    }
  }

  console.log("Calculated Combined Weight:", combinedWeight); // Expected: 45 + 12 + 55 = 112
}

testUnionArrayOps();