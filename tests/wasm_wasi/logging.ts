const TIMESTAMP: string = "2009/11/10 23:00:00";

function stdLog(msg: string): void {
    console.log(`${TIMESTAMP} ${msg}`);
}

function myLog(prefix: string, msg: string): void {
    console.log(`${TIMESTAMP} ${prefix}${msg}`);
}

stdLog("standard logger");
stdLog("with micro");
stdLog("with file/line");

myLog("my:", "from mylog");
myLog("ohmy:", "from mylog");

let buf: string = `${TIMESTAMP} buf:hello\n`;
console.log(`from buflog:${buf}`);

console.log(`{"time":"${TIMESTAMP}","level":"INFO","msg":"hi there"}`);
console.log(`{"time":"${TIMESTAMP}","level":"INFO","msg":"hello again","key":"val","age":25}`);
