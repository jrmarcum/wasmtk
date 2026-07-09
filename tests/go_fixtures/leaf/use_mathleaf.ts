// wasic program that imports + merges the alloc-free Go leaf `mathleaf.wasm`
// (built via `modc --lang=go --go-target=wasm-unknown`). Driven by go_merge_tests.ts.
import { addi, clampi, muli } from "./mathleaf.wasm";

function main(): void {
  console.log("addi:", addi(3, 4)); // 7
  console.log("muli:", muli(5, 6)); // 30
  console.log("clampi:", clampi(42, 0, 10)); // 10
}

main();
