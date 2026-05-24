enum ServerState {
    StateIdle = 0,
    StateConnected = 1,
    StateError = 2,
    StateRetrying = 3,
}

function stateName(s: ServerState): string {
    switch (s) {
        case ServerState.StateIdle: return "idle";
        case ServerState.StateConnected: return "connected";
        case ServerState.StateError: return "error";
        case ServerState.StateRetrying: return "retrying";
        default: return "unknown";
    }
}

function transition(s: ServerState): ServerState {
    switch (s) {
        case ServerState.StateIdle:
            return ServerState.StateConnected;
        case ServerState.StateConnected:
        case ServerState.StateRetrying:
            return ServerState.StateIdle;
        case ServerState.StateError:
            return ServerState.StateError;
        default:
            throw new Error(`unknown state: ${stateName(s)}`);
    }
}

const ns: ServerState = transition(ServerState.StateIdle);
console.log(stateName(ns));

const ns2: ServerState = transition(ns);
console.log(stateName(ns2));
