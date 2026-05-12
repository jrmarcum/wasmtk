function slicesIndexStr(s: string[], v: string): number {
    for (let i: number = 0; i < s.length; i++) {
        if (s[i] === v) return i;
    }
    return -1;
}

interface NumNode {
    val: number;
    hasNext: boolean;
    nextIdx: number;
}

const listNodes: NumNode[] = [];
let listHead: number = -1;
let listTail: number = -1;

function listPush(v: number): void {
    const node: NumNode = { val: v, hasNext: false, nextIdx: -1 };
    listNodes.push(node);
    const idx: number = listNodes.length - 1;
    if (listTail === -1) {
        listHead = idx;
        listTail = idx;
    } else {
        listNodes[listTail].hasNext = true;
        listNodes[listTail].nextIdx = idx;
        listTail = idx;
    }
}

function listAllElements(): number[] {
    const result: number[] = [];
    let cur: number = listHead;
    while (cur !== -1) {
        result.push(listNodes[cur].val);
        cur = listNodes[cur].hasNext ? listNodes[cur].nextIdx : -1;
    }
    return result;
}

function numArrStr(arr: number[]): string {
    let s: string = "[";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += " ";
        s += `${arr[i]}`;
    }
    return s + "]";
}

const sl: string[] = ["foo", "bar", "zoo"];
console.log("index of zoo:", slicesIndexStr(sl, "zoo"));

listPush(10);
listPush(13);
listPush(23);
console.log("list:", numArrStr(listAllElements()));
