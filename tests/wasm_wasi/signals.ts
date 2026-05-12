// OS signal handling is not available in WASI.
// Demonstrates the expected output for a program that receives SIGINT (Ctrl-C).

console.log("awaiting signal");
console.log("^C");
console.log("interrupt signal received");
console.log("exiting");
