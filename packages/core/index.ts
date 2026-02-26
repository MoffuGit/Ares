import { dlopen, FFIType, type Pointer } from "bun:ffi";
import { resolve } from "node:path";

function getCoreLib(path?: string) {
    const symbols = dlopen(
        resolve(import.meta.dir, "../../zig-out/lib/libcore.dylib"),
        {
            initState: {
                args: [],
                returns: FFIType.void,
            },
            createSettings: {
                args: [],
                returns: FFIType.pointer,
            },
            destroySettings: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            createIo: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyIo: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            createMonitor: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyMonitor: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
        },
    );

    return symbols;
}

export interface CoreLib {
    initState(): void;
    createSettings(): Pointer | null;
    destroySettings(handle: Pointer): void;
    createIo(): Pointer | null;
    destroyIo(handle: Pointer): void;
    createMonitor(): Pointer | null;
    destroyMonitor(handle: Pointer): void;
}

export class Core implements CoreLib {
    private lib: ReturnType<typeof getCoreLib>;

    constructor(path?: string) {
        this.lib = getCoreLib(path);
    }

    initState(): void {
        this.lib.symbols.initState();
    }

    createSettings(): Pointer | null {
        return this.lib.symbols.createSettings() as Pointer | null;
    }

    destroySettings(handle: Pointer): void {
        this.lib.symbols.destroySettings(handle);
    }

    createIo(): Pointer | null {
        return this.lib.symbols.createIo() as Pointer | null;
    }

    destroyIo(handle: Pointer): void {
        this.lib.symbols.destroyIo(handle);
    }

    createMonitor(): Pointer | null {
        return this.lib.symbols.createMonitor() as Pointer | null;
    }

    destroyMonitor(handle: Pointer): void {
        this.lib.symbols.destroyMonitor(handle);
    }
}
