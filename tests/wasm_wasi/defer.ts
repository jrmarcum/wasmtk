const deferred: Array<() => void> = [];

function defer(fn: () => void): void {
    deferred.push(fn);
}

function runDeferred(): void {
    for (let i: number = deferred.length - 1; i >= 0; i--) {
        deferred[i]();
    }
    deferred.length = 0;
}

console.log("counting");
for (let i: number = 0; i < 5; i++) {
    const n: number = i;
    defer(() => console.log(n));
}
console.log("done");
runDeferred();
