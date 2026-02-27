import { dlopen, FFIType, JSCallback, toArrayBuffer, type Pointer } from "bun:ffi";
import { EventEmitter } from "node:events";
import { resolve } from "node:path";
import { EventType, Events } from "./events";

function getCoreLib() {
    const symbols = dlopen(
        resolve(import.meta.dir, "../../zig-out/lib/libcore.dylib"),
        {
            initState: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            drainEvents: {
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

export class CoreLib {
    private lib: ReturnType<typeof getCoreLib>;
    private jsCallback: JSCallback | null = null;
    private _events: EventEmitter = new EventEmitter();

    get events(): EventEmitter {
        return this._events;
    }

    constructor() {
        this.lib = getCoreLib();
        this.initState();
    }

    initState(): void {
        const emitter = this._events;
        this.jsCallback = new JSCallback(
            function handleEvent(event: number, ptr: Pointer | null, len: number | bigint): void {
                const _len = typeof len === "bigint" ? Number(len) : len;
                const _type = event as EventType;
                const data_type = Events[_type];

                if (data_type == null) {
                    const event = _type.toString();
                    queueMicrotask(() => {
                        emitter.emit(event);
                    })
                } else if (data_type != null && ptr != null && _len != 0) {
                    const data = data_type.unpack(toArrayBuffer(ptr, 0, _len));
                    const event = _type.toString();
                    queueMicrotask(() => {
                        emitter.emit(event, data);
                    })

                }
            },
            {
                args: [FFIType.u8, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
        );

        if (!this.jsCallback.ptr) {
            throw new Error("Failed to create event callback")
        }

        this.lib.symbols.initState(this.jsCallback.ptr);
    }

    drainEvents(): void {
        this.lib.symbols.drainEvents();
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

let coreLib: CoreLib | undefined

export function resolveCoreLib(): CoreLib {
    if (!coreLib) {
        try {
            coreLib = new CoreLib()
        } catch (error) {
            throw new Error(
                `Failed to initialize OpenTUI render library: ${error instanceof Error ? error.message : "Unknown error"}`,
            )
        }
    }
    return coreLib
}

