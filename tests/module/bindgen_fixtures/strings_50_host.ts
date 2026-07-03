
import { loadModule } from "file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/strings_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/module/bindgen_fixtures/strings_50.wasm"));
const m = await loadModule(wasmBytes);
console.log(m.greet("World"));
console.log(m.shout("hi"));
console.log(m.strLen("hello"));
