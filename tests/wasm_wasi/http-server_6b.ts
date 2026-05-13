// HTTP servers are not available in WASI.
// Demonstrates the handler functions used to serve /hello and /headers routes.

function hello(): string {
    return "hello";
}

interface Header {
    name: string;
    value: string;
}

function headersHandler(hdrs: Header[]): string {
    let result: string = "";
    for (let i: number = 0; i < hdrs.length; i++) {
        result += `${hdrs[i].name}: ${hdrs[i].value}\n`;
    }
    return result;
}

console.log(hello());
