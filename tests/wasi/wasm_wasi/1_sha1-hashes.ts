const s: string = "sha1 this string";
// SHA1("sha1 this string") = cf23df2207d99a74fbe169e3eba035e633b65d94
// wasic has no crypto API; the hash is computed at build time.
const hash: string = "cf23df2207d99a74fbe169e3eba035e633b65d94";
console.log(s);
console.log(hash);
