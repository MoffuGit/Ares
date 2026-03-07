import { dlopen, FFIType, JSCallback, toArrayBuffer, type Pointer } from "bun:ffi";
import { resolve } from "node:path";

function getTuiLib() {
    const symbols = dlopen(
        resolve(import.meta.dir, "../../../zig-out/lib/libtui.dylib"),
        {
            initState: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            deinitState: {
                args: [],
                returns: FFIType.void,
            },
            createApp: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyApp: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            getWindow: {
                args: [FFIType.pointer],
                returns: FFIType.pointer,
            },
            createMutations: {
                args: [FFIType.pointer],
                returns: FFIType.pointer,
            },
            processMutations: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
            destroyMutations: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            dumpTree: {
                args: [FFIType.pointer],
                returns: FFIType.u64,
            },
            freeDumpTree: {
                args: [],
                returns: FFIType.void,
            },
            getDumpPtr: {
                args: [],
                returns: FFIType.pointer,
            },
            createTestWindow: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyTestWindow: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            requestDraw: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            drainMailbox: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
        },
    );

    return symbols;
}

let nextId = 1;

export function allocId(): number {
    return nextId++;
}

const mutationQueue: WireCommand[] = [];

export function enqueue(cmd: WireCommand): void {
    mutationQueue.push(cmd);
}

export type WireCommand = Record<string, unknown>;

export function drainMutations(): WireCommand[] {
    const batch = mutationQueue.slice();
    mutationQueue.length = 0;
    return batch;
}

export class TuiLib {
    private lib: ReturnType<typeof getTuiLib>;
    private jsCallback: JSCallback | null = null;

    constructor() {
        this.lib = getTuiLib();
        this.initState();
    }

    initState() {
        this.jsCallback = new JSCallback(
            function handleEvent(_event: number, _target: number, _ptr: Pointer | null, _len: number | bigint): void {
            },
            {
                args: [FFIType.u8, FFIType.u64, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
        );
        this.lib.symbols.initState(this.jsCallback.ptr)
    }

    deinitState() {
        this.lib.symbols.deinitState()
    }

    createApp(): Pointer | null {
        return this.lib.symbols.createApp()
    }

    destroyApp(app: Pointer) {
        this.lib.symbols.destroyApp(app)
    }

    drainEvents() {
        this.lib.symbols.drainEvents()
    }

    getWindow(app: Pointer): Pointer | null {
        return this.lib.symbols.getWindow(app);
    }

    createMutations(window: Pointer): Pointer | null {
        return this.lib.symbols.createMutations(window);
    }

    destroyMutations(mutations: Pointer) {
        this.lib.symbols.destroyMutations(mutations);
    }

    processMutations(mutationsPtr: Pointer) {
        const batch = drainMutations();
        if (batch.length === 0) return;

        const payload = JSON.stringify(batch);
        const encoded = new TextEncoder().encode(payload);

        this.lib.symbols.processMutations(mutationsPtr, encoded, encoded.byteLength);
    }

    createTestWindow(): Pointer | null {
        return this.lib.symbols.createTestWindow();
    }

    destroyTestWindow(window: Pointer) {
        this.lib.symbols.destroyTestWindow(window);
    }

    dumpTree(window: Pointer): object | null {
        const rawLen = this.lib.symbols.dumpTree(window);
        const len = Number(rawLen);
        if (len === 0) return null;

        const ptr = this.lib.symbols.getDumpPtr()!;
        const buf = new Uint8Array(toArrayBuffer(ptr, 0, len));
        const jsonStr = new TextDecoder().decode(buf);
        this.lib.symbols.freeDumpTree();
        return JSON.parse(jsonStr);
    }

    requestDraw(app: Pointer) {
        this.lib.symbols.requestDraw(app);
    }

    drainMailbox(app: Pointer) {
        this.lib.symbols.drainMailbox(app);
    }
}

let tuiLib: TuiLib | undefined;

export function resolveTuiLib(): TuiLib {
    if (!tuiLib) {
        try {
            tuiLib = new TuiLib();
        } catch (error) {
            throw new Error("Failed to initialize the tui lib");
        }
    }
    return tuiLib;
}
