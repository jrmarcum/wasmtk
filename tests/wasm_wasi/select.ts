function makeMessage(tag: string): string {
    return tag;
}

const c1: string = makeMessage("one");
const c2: string = makeMessage("two");

// select-style dispatch: process whichever "arrives" first (sequential here)
console.log("received", c1);
console.log("received", c2);
