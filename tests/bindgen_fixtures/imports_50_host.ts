
import { loadModule } from "file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/imports_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/imports_50.wasm"));
const m = await loadModule(wasmBytes, {
  env: {
    envMul: (a, b) => a * b,
    envAdd: (a, b) => a + b,
  }
});
console.log(m.scale(3.0, 4.0));
console.log(m.combine(10, 7));
