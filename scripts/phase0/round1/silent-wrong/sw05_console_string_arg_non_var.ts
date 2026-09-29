type i32 = number;
function count(s: string): i32 { return s.length; }
const names: string[] = ["a", "bcd"];
console.log(count(names[1]));
