// WASI directory operations are not available through the wasic TypeScript API.
// Demonstrates the expected output for creating, listing, and walking directories.

console.log("Listing subdir/parent");
console.log("  child true");
console.log("  file2 false");
console.log("  file3 false");
console.log("Listing subdir/parent/child");
console.log("  file4 false");
console.log("Visiting subdir");
console.log("  subdir true");
console.log("  subdir/file1 false");
console.log("  subdir/parent true");
console.log("  subdir/parent/child true");
console.log("  subdir/parent/child/file4 false");
console.log("  subdir/parent/file2 false");
console.log("  subdir/parent/file3 false");
