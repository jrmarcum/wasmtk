
import { loadModule } from "file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/strings_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///run/media/jonmarcum/3285-B831/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/strings_50.wasm"));
const m = await loadModule(wasmBytes);
console.log(m.greet("World"));
console.log(m.shout("hi"));
console.log(m.strLen("hello"));
