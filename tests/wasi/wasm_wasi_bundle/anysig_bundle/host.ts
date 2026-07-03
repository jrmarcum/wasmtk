import { loadModule } from "./anysig_lib.bindings.ts";
const lib = await loadModule(new URL("./anysig_lib.wasm", import.meta.url));
console.log("identity(42) =", lib.identity(42));
console.log("identity('hi') =", lib.identity("hi"));
console.log("identity(true) =", lib.identity(true));
console.log("addOne(41) =", lib.addOne(41));
console.log("typeName(42) =", lib.typeName(42));
console.log("typeName('x') =", lib.typeName("x"));
console.log("typeName(true) =", lib.typeName(true));
console.log("exclaim('wow') =", lib.exclaim("wow"));
console.log("makePoint(3,4) =", JSON.stringify(lib.makePoint(3, 4)));
console.log("triple(1,2,3) =", JSON.stringify(lib.triple(1, 2, 3)));
console.log("sumArr([10,20,30]) =", lib.sumArr([10, 20, 30]));
console.log("getX({x:42,y:7}) =", lib.getX({ x: 42, y: 7 }));

// #14 final item — a core function returned as a callable JS proxy (pinned, calls back via dynApply)
const doubler = lib.getDoubler() as ((x: number) => number) & { release(): void };
console.log("getDoubler()(21) =", doubler(21));
doubler.release();
