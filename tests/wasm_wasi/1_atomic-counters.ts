let ops: number = 0;

for (let i: number = 0; i < 50; i++) {
    for (let j: number = 0; j < 1000; j++) {
        ops++;
    }
}

console.log("ops:", ops);
