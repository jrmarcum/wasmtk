// In wasic TypeScript, the process exit code cannot be set from user code.
// throw exits immediately without running deferred calls, mirroring os.Exit behavior.
// In Go, go run reports "exit status 3"; here we print the equivalent concept.

const deferred: Array<() => void> = [];
function defer(fn: () => void): void {
    deferred.push(fn);
}

function runDeferred(): void {
    for (let i: number = deferred.length - 1; i >= 0; i--) {
        deferred[i]();
    }
}

defer(() => console.log("!"));

// throw exits immediately; deferred calls are bypassed
console.log("exit status 3");
