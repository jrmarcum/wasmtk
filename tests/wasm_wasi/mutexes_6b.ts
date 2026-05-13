interface Counters {
    a: number;
    b: number;
}

function doIncrement(c: Counters, name: string, n: number): void {
    for (let i: number = 0; i < n; i++) {
        if (name === "a") {
            c.a++;
        } else {
            c.b++;
        }
    }
}

const c: Counters = { a: 0, b: 0 };

doIncrement(c, "a", 10000);
doIncrement(c, "a", 10000);
doIncrement(c, "b", 10000);

console.log(`map[a:${c.a} b:${c.b}]`);
