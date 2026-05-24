function f(from: string): void {
    for (let i: number = 0; i < 3; i++) {
        console.log(from, ":", i);
    }
}

f("direct");
f("goroutine");
console.log("going");
console.log("done");
