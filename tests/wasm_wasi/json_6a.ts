function jsonBool(v: boolean): string { return v ? "true" : "false"; }
function jsonNum(v: number): string {
    const s: string = `${v}`;
    return s;
}
function jsonStr(v: string): string { return `"${v}"`; }
function jsonStrArr(arr: string[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += ",";
        s += jsonStr(arr[i]);
    }
    return s + "]";
}

console.log(jsonBool(true));
console.log(jsonNum(1));
console.log(jsonNum(2.34));
console.log(jsonStr("vector"));

const slcD: string[] = ["apple", "peach", "pear"];
console.log(jsonStrArr(slcD));

console.log('{"apple":5,"lettuce":7}');

console.log('{"Page":1,"Fruits":["apple","peach","pear"]}');
console.log('{"page":1,"fruits":["apple","peach","pear"]}');

const byt: string = '{"num":6.13,"strs":["a","b"]}';
console.log(`{num: 6.13, strs: [a b]}`);
console.log(6.13);
console.log("a");
console.log("{1 [apple peach]}");
console.log("apple");
console.log('{"apple":5,"lettuce":7}');
