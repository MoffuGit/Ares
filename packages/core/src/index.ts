import { dlopen, FFIType, JSCallback, ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { EventEmitter } from "node:events";
import { resolve } from "node:path";
import { EventType, Events } from "./events";
import { Settings, Theme, WorktreeEntry } from "./structs";

const DEFAULT_LIB_PATH = resolve(import.meta.dir, "../../../zig-out/lib/libcore.dylib");

function getCoreLib(libPath: string) {
    const symbols = dlopen(
        libPath,
        {
            initState: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            deinitState: {
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
            lockSettings: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            unlockSettings: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            loadSettings: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64, FFIType.pointer],
                returns: FFIType.void,
            },
            readSettings: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.void,
            },
            readTheme: {
                args: [FFIType.pointer, FFIType.pointer],
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
            createProject: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.pointer, FFIType.u64],
                returns: FFIType.pointer,
            },
            destroyProject: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            getWorktreeEntryCount: {
                args: [FFIType.pointer],
                returns: FFIType.u64,
            },
            readWorktreeEntries: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
                returns: FFIType.u64,
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

    constructor(libPath?: string) {
        this.lib = getCoreLib(libPath ?? DEFAULT_LIB_PATH);
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
                threadsafe: true
            },
        );

        if (!this.jsCallback.ptr) {
            throw new Error("Failed to create event callback")
        }

        this.lib.symbols.initState(this.jsCallback.ptr);
    }

    deinitState(): void {
        this.lib.symbols.deinitState();
    }

    createSettings(): Pointer | null {
        return this.lib.symbols.createSettings() as Pointer | null;
    }

    destroySettings(handle: Pointer): void {
        this.lib.symbols.destroySettings(handle);
    }

    loadSettings(settings: Pointer, path: string, monitor: Pointer): void {
        const buf = new TextEncoder().encode(path);
        this.lib.symbols.loadSettings(settings, buf, buf.byteLength, monitor);
    }

    readSettings(settings: Pointer) {
        this.lib.symbols.lockSettings(settings);
        try {
            const buf = new ArrayBuffer(Settings.size);
            this.lib.symbols.readSettings(settings, ptr(buf));
            return Settings.unpack(buf);
        } finally {
            this.lib.symbols.unlockSettings(settings);
        }
    }

    readTheme(settings: Pointer) {
        this.lib.symbols.lockSettings(settings);
        try {
            const buf = new ArrayBuffer(Theme.size);
            this.lib.symbols.readTheme(settings, ptr(buf));
            return Theme.unpack(buf);
        } finally {
            this.lib.symbols.unlockSettings(settings);
        }
    }

    createIo(): Pointer | null {
        return this.lib.symbols.createIo();
    }

    destroyIo(handle: Pointer): void {
        this.lib.symbols.destroyIo(handle);
    }

    createMonitor(): Pointer | null {
        return this.lib.symbols.createMonitor();
    }

    destroyMonitor(handle: Pointer): void {
        this.lib.symbols.destroyMonitor(handle);
    }

    createProject(monitor: Pointer, io: Pointer, path: string): Pointer | null {
        const buf = new TextEncoder().encode(path);
        return this.lib.symbols.createProject(monitor, io, buf, buf.byteLength) as Pointer | null;
    }

    destroyProject(handle: Pointer): void {
        this.lib.symbols.destroyProject(handle);
    }

    readWorktreeEntries(project: Pointer) {
        const count = Number(this.lib.symbols.getWorktreeEntryCount(project));
        if (count === 0) return [];

        const entrySize = WorktreeEntry.size;
        const buf = new ArrayBuffer(count * entrySize);
        const actual = Number(this.lib.symbols.readWorktreeEntries(project, ptr(buf), count));

        const entries: ReturnType<typeof WorktreeEntry.unpack>[] = [];
        for (let i = 0; i < actual; i++) {
            const slice = buf.slice(i * entrySize, (i + 1) * entrySize);
            entries.push(WorktreeEntry.unpack(slice));
        }
        return entries;
    }

}

let coreLib: CoreLib | undefined

export function resolveCoreLib(libPath?: string): CoreLib {
    if (!coreLib) {
        try {
            coreLib = new CoreLib(libPath)
        } catch (error) {
            throw new Error(
                `Failed to initialize the core lib`,
            )
        }
    }
    return coreLib
}

