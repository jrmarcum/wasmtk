
import { loadModule } from "file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/booleans_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/booleans_50.wasm"));
const m = await loadModule(wasmBytes);
console.log(m.isPositive(1.0));
console.log(m.isPositive(-1.0));
console.log(m.inRange(5.0, 1.0, 10.0));
console.log(m.inRange(0.0, 1.0, 10.0));
console.log(m.isEven(4));
console.log(m.isEven(3));
