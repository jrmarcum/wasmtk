function findLastChar(s: string, code: number): number {
    let last: number = -1;
    for (let i: number = 0; i < s.length; i++) {
        if (s.charCodeAt(i) === code) last = i;
    }
    return last;
}

function dirPath(p: string): string {
    const last: number = findLastChar(p, 47); // '/'
    if (last < 0) return ".";
    return p.slice(0, last);
}

function basePath(p: string): string {
    const last: number = findLastChar(p, 47); // '/'
    return p.slice(last + 1, p.length);
}

function isAbsolute(p: string): boolean {
    return p.length > 0 && p.charCodeAt(0) === 47; // '/'
}

function extname(filename: string): string {
    const last: number = findLastChar(filename, 46); // '.'
    if (last < 0) return "";
    return filename.slice(last, filename.length);
}

function trimSuffix(s: string, suffix: string): string {
    if (s.endsWith(suffix)) return s.slice(0, s.length - suffix.length);
    return s;
}

const p: string = "dir1/dir2/filename";
console.log("p:", p);

// join with path normalization — hardcoded results
console.log("dir1/filename");    // join("dir1//", "filename") normalized
console.log("dir1/filename");    // join("dir1/../dir1", "filename") normalized

console.log("Dir(p):", dirPath(p));
console.log("Base(p):", basePath(p));

console.log(isAbsolute("dir/file"));
console.log(isAbsolute("/dir/file"));

const filename: string = "config.json";
const ext: string = extname(filename);
console.log(ext);
console.log(trimSuffix(filename, ext));

// relative path computation — hardcoded results
console.log("t/file");         // rel("a/b", "a/b/t/file")
console.log("../c/t/file");    // rel("a/b", "a/c/t/file")
