import type { Mode, ParsedKeymaps } from "@ares/shared";
import {
    type CmdScope,
    type ScopeCmdDefinition,
    resolveScopeCmd,
} from "./cmds.ts";

export type { CmdScope } from "./cmds.ts";

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
    exclusive: boolean;
};

export type CmdEventListenerOptions = {
    /**
     * When true, this listener consumes the sequence: no further (older)
     * listeners are notified, even when this scope has no matching cmd.
     */
    exclusive?: boolean;
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

    on<Scope extends CmdScope>(
        scope: Scope,
        listener: CmdEventListener<Scope>,
        options?: CmdEventListenerOptions,
    ): () => void;
    on<Scope extends CmdScope>(
        scope: Scope,
        listener: CmdEventListener<Scope>,
        options: CmdEventListenerOptions = {},
    ) {
        const entry: ListenerEntry = {
            scope,
            listener,
            exclusive: options.exclusive ?? false,
        };
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
            const entry = listeners[i];
            const cmdKey = findScopeCommand(keymaps, entry.scope, mode, sequence);

            if (cmdKey) {
                const cmd = resolveScopeCmd(entry.scope, mode, cmdKey);
                if (cmd) {
                    matched = true;
                    entry.listener(new CmdEvent({ cmd, mode, scope: entry.scope, sequence }, propagationState));
                }
            }

            if (propagationState.stopped) {
                break;
            }

            if (entry.exclusive) {
                propagationState.stopped = true;
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
