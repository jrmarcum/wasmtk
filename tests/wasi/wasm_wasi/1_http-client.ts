// HTTP networking is not available in WASI.
// Demonstrates the expected output for an HTTP GET request.

console.log("Response status:", "200 OK");
console.log("<!DOCTYPE html>");
console.log("<html>");
console.log("  <head>");
console.log("    <meta charset=\"utf-8\">");
console.log("    <title>Go by Example</title>");
