function greet(name: string): string {
    return "Hello, " + name;
}

function formatNum(n: i32): string {
    return `value=${n}`;
}

function describe(label: string, n: i32): string {
    return label + "=" + formatNum(n);
}

const msg: string = greet("World");
console.log(msg);
console.log(greet("Alice"));
console.log(formatNum(42));
console.log("result:", greet("Bob"));
console.log(describe("x", 7));
