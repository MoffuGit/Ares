import { dlopen, FFIType, JSCallback, type Pointer } from "bun:ffi";
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
            drainEvents: {
                args: [],
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
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64]
            }
        },
    );

    return symbols;
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
            function handleEvent(event: number, target: number, ptr: Pointer | null, len: number | bigint): void {
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

    processMutation(mutations: Pointer) {

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
