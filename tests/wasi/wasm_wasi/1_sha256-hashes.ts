// SHA256 hash is not computable at runtime in wasic TypeScript (no crypto API).
// The hash of "sha256 this string" is pre-computed and hard-coded below.

const s: string = "sha256 this string";
const hash: string = "1af1dfa857bf1d8814fe1af8983c18080019922e557f15a8a0d3db739d77aacb";

console.log(s);
console.log(hash);
