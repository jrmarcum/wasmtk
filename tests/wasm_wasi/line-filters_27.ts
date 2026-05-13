// WASI stdin reading is not available through the wasic TypeScript API.
// Demonstrates line filtering with hardcoded input lines.

const lines: string[] = ["hello", "filter"];
for (let i: number = 0; i < lines.length; i++) {
    console.log(lines[i].toUpperCase());
}
