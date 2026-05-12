let message: string = "";

function send(msg: string): void {
    message = msg;
}

function receive(): string {
    return message;
}

send("ping");
const msg: string = receive();
console.log(msg);
