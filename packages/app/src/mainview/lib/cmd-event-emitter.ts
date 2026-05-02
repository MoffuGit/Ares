import type { Mode, ParsedKeymaps } from "@ares/shared";
import {
    type CmdScope,
    type ScopeCmdDefinition,
    resolveScopeCmd,
} from "./cmd-definitions.ts";

export type { CmdScope } from "./cmd-definitions.ts";

export type CmdEventInit<Scope extends CmdScope = CmdScope> = {
    cmd: ScopeCmdDefinition<Scope>;
    mode: Mode;
    scope: Scope;
    sequence: string;
};

export type CmdEventListener<Scope extends CmdScope = CmdScope> = (event: CmdEvent<Scope>) => void;

export type CmdEventEmitResult = {
    matched: boolean;
    propagationStopped: boolean;
};

type ListenerEntry = {
    scope: CmdScope;
    listener: CmdEventListener<any>;
};

type PropagationState = {
    stopped: boolean;
};

export class CmdEvent<Scope extends CmdScope = CmdScope> {
    readonly cmd: ScopeCmdDefinition<Scope>;
    readonly mode: Mode;
    readonly sequence: string;
    readonly scope: Scope;
    private readonly propagationState: PropagationState;

    constructor(init: CmdEventInit<Scope>, propagationState: PropagationState) {
        this.cmd = init.cmd;
        this.mode = init.mode;
        this.sequence = init.sequence;
        this.scope = init.scope;
        this.propagationState = propagationState;
    }

    get propagationStopped() {
        return this.propagationState.stopped;
    }

    stopPropagation() {
        this.propagationState.stopped = true;
    }
}

export class CmdEventEmitter {
    private readonly listeners: ListenerEntry[] = [];

    on(scope: "global", listener: CmdEventListener<"global">): () => void;
    on<Scope extends CmdScope>(scope: Scope, listener: CmdEventListener<Scope>): () => void;
    on<Scope extends CmdScope>(scope: Scope, listener: CmdEventListener<Scope>) {
        const entry: ListenerEntry = { scope, listener };
        this.listeners.push(entry);

        return () => {
            const index = this.listeners.indexOf(entry);
            if (index !== -1) {
                this.listeners.splice(index, 1);
            }
        };
    }

    emitSequence(sequence: string, keymaps: ParsedKeymaps | null | undefined, mode: Mode): CmdEventEmitResult {
        if (!keymaps) {
            return { matched: false, propagationStopped: false };
        }

        const propagationState: PropagationState = { stopped: false };
        let matched = false;
        const listeners = [...this.listeners];

        // Newer listeners get the first chance to handle a sequence and stop it.
        for (let i = listeners.length - 1; i >= 0; i -= 1) {
            const listener = listeners[i];
            const cmdKey = findScopeCommand(keymaps, listener.scope, mode, sequence);
            if (!cmdKey) continue;

            const cmd = resolveScopeCmd(listener.scope, mode, cmdKey);
            if (!cmd) continue;

            matched = true;
            listener.listener(new CmdEvent({ cmd, mode, scope: listener.scope, sequence }, propagationState));

            if (propagationState.stopped) {
                break;
            }
        }

        return {
            matched,
            propagationStopped: propagationState.stopped,
        };
    }
}

export const cmdEventEmitter = new CmdEventEmitter();

function findScopeCommand(keymaps: ParsedKeymaps, scope: CmdScope, mode: Mode, sequence: string) {
    const scopeKeymaps = keymaps[scope]?.[mode];
    if (!scopeKeymaps) return null;

    const match = scopeKeymaps.find((keymap) => keymap.sequence === sequence);
    return match?.cmd ?? null;
}
