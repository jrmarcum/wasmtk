
import { loadModule } from "file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/fnany_50.bindings.ts";
const wasmBytes = await Deno.readFile(new URL("file:///D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/wasmtk/tests/bindgen_fixtures/fnany_50.wasm"));
const m = await loadModule(wasmBytes);
const dbl = m.getDoubler() as ((x: number) => number) & { release(): void };
console.log(dbl(21));
dbl.release();
