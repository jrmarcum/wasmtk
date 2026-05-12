interface Base {
    num: number;
}

function baseDescribe(b: Base): string {
    return `base with num=${b.num}`;
}

interface Container {
    base: Base;
    str: string;
}

function newContainer(num: number, str: string): Container {
    return { base: { num }, str };
}

function containerDescribe(co: Container): string {
    return baseDescribe(co.base);
}

interface Describer {
    describe: () => string;
}

const co: Container = newContainer(1, "some name");
console.log(`co={num: ${co.base.num}, str: ${co.str}}`);
console.log("also num:", co.base.num);
console.log("describe:", containerDescribe(co));

const descFn: () => string = () => containerDescribe(co);
console.log("describer:", descFn());
