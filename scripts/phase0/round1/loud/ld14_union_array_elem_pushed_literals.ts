type i32 = number;
interface Leaf { type: "leaf"; weight: i32; }
interface Inner { type: "inner"; count: i32; }
type TreeItem = Leaf | Inner;
const xs: TreeItem[] = [];
xs.push({ type: "leaf", weight: 3 });
xs.push({ type: "inner", count: 5 });
let s: i32 = 0;
for (let i = 0; i < xs.length; i++) {
  const n: TreeItem = xs[i];
  if (n.type === "leaf") {
    s = s + n.weight;
  } else {
    s = s + n.count;
  }
}
console.log(s);
