
import { loadModule } from "file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/kebabcase_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/kebabcase_50.wasm"));
const m = await loadModule(wasmBytes);
// Binding methods use the WIT-derived camelCase (readId/toHtml); _ex() bridges
// them to the original-cased wasm exports readID/toHTML at call time.
console.log(m.readId(41));
console.log(m.toHtml(21));
