
import { loadModule } from "file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/booleans_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/booleans_50.wasm"));
const m = await loadModule(wasmBytes);
console.log(m.isPositive(1.0));
console.log(m.isPositive(-1.0));
console.log(m.inRange(5.0, 1.0, 10.0));
console.log(m.inRange(0.0, 1.0, 10.0));
console.log(m.isEven(4));
console.log(m.isEven(3));
