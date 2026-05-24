// TCP networking is not available in WASI.
// Demonstrates the message-echo concept: uppercasing the received message.

function handleConnection(msg: string): void {
    const trimmed: string = msg.trim();
    const upper: string = trimmed.toUpperCase();
    console.log(`ACK: ${upper}`);
}

handleConnection("hello tcp");
