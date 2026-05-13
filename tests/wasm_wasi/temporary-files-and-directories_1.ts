// WASI temporary file and directory creation is not available through the wasic TypeScript API.
// Demonstrates the expected output format with example path names.

const tmpFile: string = "/tmp/sample123456789";
console.log("Temp file name:", tmpFile);

const tmpDir: string = "/tmp/sampledir987654321";
console.log("Temp dir name:", tmpDir);
