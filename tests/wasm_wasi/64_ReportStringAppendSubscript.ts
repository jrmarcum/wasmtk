// deno-fmt-ignore-file
// Report issue 2 (HIGH): `str += someString[index]` aborted (`$__str_op_ptr cannot be resolved`) — the
// `+=` char-subscript RHS needed the $__str_op temp pair, which the pre-scan trigger missed.
type i32 = number;
const chars: string = "ABCD";
let result: string = "";
result += chars[2];
result += chars[0];
console.log(result);
function rev(s: string): string { let out: string = ""; for (let i: i32 = 0; i < s.length; i++) { out += s[i]; } return out; }
console.log(rev("xyz"));
