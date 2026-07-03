// Regression: assigning a string-METHOD-call-on-an-array-element to a string variable
// (`const u = words[0].toUpperCase()`). emitStringAssign previously fell to its complex-expression
// stub (empty result); it now delegates a last resort to emitStringPtrLen, which resolves a string
// method on a bracket receiver. (join()-as-a-value and slice() on a bracket receiver remain gaps.)

type i32 = number;

const words: string[] = ["abc", "def", "ghi"];

const u: string = words[0].toUpperCase();
const l: string = words[1].toLowerCase();
const u2: string = words[2].toUpperCase();
const plain: string = words[1]; // plain element (already worked)

console.log(u); // ABC
console.log(l); // def
console.log(u2); // GHI
console.log(plain); // def
console.log(u + "-" + l); // ABC-def (in a concat)
