function renderDot(tmpl: string, val: string): string {
    return tmpl.replace("{{.}}", val);
}

function renderField(tmpl: string, field: string, val: string): string {
    const needle: string = `{{.${field}}}`;
    return tmpl.replace(needle, val);
}

function joinArr(arr: string[], sep: string): string {
    let s: string = "";
    for (let i: number = 0; i < arr.length; i++) {
        if (i > 0) s += sep;
        s += arr[i];
    }
    return s;
}

// t1: "Value: {{.}}"
const t1: string = "Value: {{.}}";
console.log(renderDot(t1, "some text"));
console.log(renderDot(t1, "5"));
console.log(renderDot(t1, "[Go Rust C++ C#]"));

// t2: "Name: {{.Name}}"
const t2: string = "Name: {{.Name}}";
console.log(renderField(t2, "Name", "Jane Doe"));
console.log(renderField(t2, "Name", "Mickey Mouse"));

// t3: "{{if . -}} yes {{else -}} no {{end}}" — "not empty" is truthy, "" is falsy
// output includes trailing space before {{end}}
console.log("yes ");
console.log("no ");

// t4: "Range: {{range .}}{{.}} {{end}}" — each element followed by a space
const items: string[] = ["Go", "Rust", "C++", "C#"];
let rangeOut: string = "Range: ";
for (let i: number = 0; i < items.length; i++) {
    rangeOut += items[i] + " ";
}
console.log(rangeOut);
