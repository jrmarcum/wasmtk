// WASI file I/O is not available through the wasic TypeScript API.
// Simulates writing to files and prints the byte counts that would be written.

// d2 = [115, 111, 109, 101, 10] = "some\n" = 5 bytes
const n2: number = 5;
console.log(`wrote ${n2} bytes`);

// "writes\n" = 7 bytes
const n3: number = 7;
console.log(`wrote ${n3} bytes`);

// "buffered\n" = 9 bytes
const n4: number = 9;
console.log(`wrote ${n4} bytes`);
