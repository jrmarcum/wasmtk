
// auto-generated host runner for math_50 bindgen test
import { loadModule } from "file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/math_50.bindings.ts";

const wasmBytes = await Deno.readFile(new URL("file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/math_50.wasm"));
const m = await loadModule(wasmBytes);
console.log(m.add(3, 4));
console.log(m.multiply(2.5, 4.0));
console.log(m.square(5));
