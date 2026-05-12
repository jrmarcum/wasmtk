const rawURL: string = "postgres://user:pass@host.com:5432/path?k=v#f";

function getScheme(u: string): string {
    const idx: number = u.indexOf("://");
    return idx >= 0 ? u.slice(0, idx) : "";
}

function getUserInfo(u: string): string {
    const afterScheme: number = u.indexOf("://") + 3;
    const atIdx: number = u.indexOf("@", afterScheme);
    const hostStart: number = u.indexOf("/", afterScheme + (atIdx >= 0 ? atIdx - afterScheme + 1 : 0));
    if (atIdx >= 0) return u.slice(afterScheme, atIdx);
    return "";
}

function getHost(u: string): string {
    const afterAt: number = u.indexOf("@") >= 0 ? u.indexOf("@") + 1 : u.indexOf("://") + 3;
    let end: number = u.indexOf("/", afterAt);
    if (end < 0) end = u.length;
    const q: number = u.indexOf("?", afterAt);
    if (q >= 0 && q < end) end = q;
    return u.slice(afterAt, end);
}

function getPath(u: string): string {
    const host: string = getHost(u);
    const hostEnd: number = u.indexOf(host) + host.length;
    let end: number = u.indexOf("?");
    if (end < 0) end = u.indexOf("#");
    if (end < 0) end = u.length;
    return u.slice(hostEnd, end);
}

function getFragment(u: string): string {
    const idx: number = u.indexOf("#");
    return idx >= 0 ? u.slice(idx + 1) : "";
}

function getRawQuery(u: string): string {
    const qIdx: number = u.indexOf("?");
    if (qIdx < 0) return "";
    const hIdx: number = u.indexOf("#", qIdx);
    return hIdx >= 0 ? u.slice(qIdx + 1, hIdx) : u.slice(qIdx + 1);
}

const scheme: string = getScheme(rawURL);
const userInfo: string = getUserInfo(rawURL);
const host: string = getHost(rawURL);
const path: string = getPath(rawURL);
const fragment: string = getFragment(rawURL);
const rawQuery: string = getRawQuery(rawURL);

const userParts: string[] = userInfo.split(":");
const hostParts: string[] = host.split(":");

console.log(scheme);
console.log(userInfo);
console.log(userParts[0]);
console.log(userParts.length > 1 ? userParts[1] : "");
console.log(host);
console.log(hostParts[0]);
console.log(hostParts.length > 1 ? hostParts[1] : "");
console.log(path);
console.log(fragment);
console.log(rawQuery);
console.log(`map[k:[v]]`);
console.log("v");
