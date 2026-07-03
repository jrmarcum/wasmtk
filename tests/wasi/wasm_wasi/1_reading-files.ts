// WASI file I/O is not available through the wasic TypeScript API.
// Simulates reading tmp/dat.txt (content: "hello\ngo\n").

console.log("hello");
console.log("go");

const n1: number = 5;
console.log(`${n1} bytes: hello`);

const n2: number = 2;
const o2: number = 6;
console.log(`${n2} bytes @ ${o2}: go`);

const n3: number = 2;
const o3: number = 6;
console.log(`${n3} bytes @ ${o3}: go`);

console.log("5 bytes: hello");
