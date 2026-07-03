// Dynamic stdlib: JSON, Map, Set, String methods, Math, try/catch — all interpreted.
const obj = JSON.parse('{"name":"wasmtk","nums":[1,2,3]}');
console.log("name:", obj.name);
console.log("nums:", JSON.stringify(obj.nums));
console.log("restringify:", JSON.stringify(obj));

const m = new Map();
m.set("a", 1);
m.set("b", 2);
m.set("a", 9);
console.log("map a:", m.get("a"), "size:", m.size);

const set = new Set([1, 2, 2, 3, 3, 3]);
console.log("set size:", set.size, "has 2:", set.has(2));

const s = "Hello, World";
console.log("upper:", s.toUpperCase(), "len:", s.length, "slice:", s.slice(0, 5));
console.log("includes:", s.includes("World"), "idx:", s.indexOf("World"));

console.log("math:", Math.max(3, 7, 2), Math.min(3, 7, 2), Math.abs(-5));

let caught = "none";
try {
  throw "boom";
} catch (e) {
  caught = "caught:" + e;
}
console.log("try:", caught);
