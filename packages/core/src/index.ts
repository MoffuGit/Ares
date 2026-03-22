import { dlopen, FFIType, JSCallback, ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { EventEmitter } from "events";
import { resolve } from "path";
import { EventType, Events, EventsName } from "./events";
import { BufferData, KeymapEntry, Settings, WorktreeEntry } from "./structs";

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
            createAppearance: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyAppearance: {
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
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64, FFIType.pointer, FFIType.pointer],
                returns: FFIType.void,
            },
            readSettings: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.void,
            },
            getThemeJsonLen: {
                args: [FFIType.pointer],
                returns: FFIType.u64,
            },
            readThemeJson: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
            setWindowTrafficLightsPosition: {
                args: [FFIType.ptr, FFIType.f64, FFIType.f64],
                returns: FFIType.bool,
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
            getFiletreeCount: {
                args: [FFIType.pointer],
                returns: FFIType.u64,
            },
            readFiletree: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
                returns: FFIType.u64,
            },
            lockWorktree: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            unlockWorktree: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            expandEntry: {
                args: [FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
            getTrieRoot: {
                args: [FFIType.pointer, FFIType.u8],
                returns: FFIType.pointer,
            },
            trieStep: {
                args: [FFIType.pointer, FFIType.u32, FFIType.u8],
                returns: FFIType.pointer,
            },
            trieNodeIsTerminal: {
                args: [FFIType.pointer],
                returns: FFIType.bool,
            },
            trieNodeHasChildren: {
                args: [FFIType.pointer],
                returns: FFIType.bool,
            },
            getKeymapEntryCount: {
                args: [FFIType.pointer, FFIType.u8, FFIType.u8],
                returns: FFIType.u64,
            },
            readKeymapEntries: {
                args: [FFIType.pointer, FFIType.u8, FFIType.u8, FFIType.pointer, FFIType.u64],
                returns: FFIType.u64,
            },
            openBuffer: {
                args: [FFIType.pointer, FFIType.u64],
                returns: FFIType.pointer
            },
            closeBuffer: {
                args: [FFIType.pointer, FFIType.u64],
                returns: FFIType.void
            },
            readBuffer: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.void
            },
            setSystemScheme: {
                args: [FFIType.pointer, FFIType.u8],
                returns: FFIType.void,
            },
            drainMailbox: {
                args: [],
                return: FFIType.void,
            },
            gpuInit: {
                args: [FFIType.pointer],
                returns: FFIType.pointer,
            },
            gpuStartRenderLoop: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            gpuResize: {
                args: [FFIType.pointer, FFIType.u32, FFIType.u32],
                returns: FFIType.void,
            },
            gpuDestroy: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            }
        },
    );

    return symbols;
}

export class CoreLib extends EventEmitter {
    private lib: ReturnType<typeof getCoreLib>;
    private jsCallback: JSCallback | null = null;


    constructor(libPath?: string) {
        super();
        this.lib = getCoreLib(libPath ?? DEFAULT_LIB_PATH);
        this.initState();
    }

    initState(): void {
        this.jsCallback = new JSCallback(
            (event: number, ptr: Pointer | null, len: number | bigint): void => {
                const _len = typeof len === "bigint" ? Number(len) : len;
                const _type = event as EventType;
                const dataType = Events[_type];

                if (dataType == null) {
                    const event = EventsName[_type];
                    queueMicrotask(() => {
                        console.log("event received", event);
                        this.emit(event);
                    })
                } else if (dataType != null && ptr != null && _len != 0) {
                    if (dataType.size != _len) {
                        console.log("expected size: ", dataType.size, "got: ", _len);
                        return
                    };
                    const data = dataType.unpack(toArrayBuffer(ptr, 0, _len));
                    const event = EventsName[_type];
                    queueMicrotask(() => {
                        console.log("event received", event);
                        this.emit(event, data);
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

    createAppearance(): Pointer | null {
        return this.lib.symbols.createAppearance() as Pointer | null;
    }

    destroyAppearance(handle: Pointer): void {
        this.lib.symbols.destroyAppearance(handle);
    }

    setWindowTrafficLightsPosition(window: Pointer, x: number, y: number) {
        this.lib.symbols.setWindowTrafficLightsPosition(window, x, y);
    }

    loadSettings(settings: Pointer, path: string, monitor: Pointer, appearance?: Pointer | null): void {
        const buf = new TextEncoder().encode(path);
        this.lib.symbols.loadSettings(settings, buf, buf.byteLength, monitor, appearance ?? null);
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

    readThemeJson(settings: Pointer): string {
        this.lib.symbols.lockSettings(settings);
        try {
            const len = Number(this.lib.symbols.getThemeJsonLen(settings));
            if (len === 0) return "{}";
            const buf = new ArrayBuffer(len);
            this.lib.symbols.readThemeJson(settings, ptr(buf), len);
            return new TextDecoder().decode(buf);
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

    readFileTree(project: Pointer) {
        this.lib.symbols.lockWorktree(project);

        const count = Number(this.lib.symbols.getFiletreeCount(project));
        if (count === 0) return [];

        const entrySize = WorktreeEntry.size;
        const buf = new ArrayBuffer(count * entrySize);
        const actual = Number(this.lib.symbols.readFiletree(project, ptr(buf), count));

        const entries: ReturnType<typeof WorktreeEntry.unpack>[] = [];
        for (let i = 0; i < actual; i++) {
            const slice = buf.slice(i * entrySize, (i + 1) * entrySize);
            entries.push(WorktreeEntry.unpack(slice));
        }

        this.lib.symbols.unlockWorktree(project);
        return entries;
    }

    expandEntry(project: Pointer, id: number): void {
        this.lib.symbols.expandEntry(project, id);
    }

    getTrieRoot(settings: Pointer, mode: number): Pointer | null {
        return this.lib.symbols.getTrieRoot(settings, mode) as Pointer | null;
    }

    trieStep(node: Pointer, codepoint: number, mods: number): Pointer | null {
        return this.lib.symbols.trieStep(node, codepoint, mods) as Pointer | null;
    }

    trieNodeIsTerminal(node: Pointer): boolean {
        return this.lib.symbols.trieNodeIsTerminal(node) as boolean;
    }

    trieNodeHasChildren(node: Pointer): boolean {
        return this.lib.symbols.trieNodeHasChildren(node) as boolean;
    }

    readKeymapEntries(settings: Pointer, scope: number, mode: number): Array<{ sequence: string; action: string }> {
        this.lib.symbols.lockSettings(settings);
        try {
            const count = Number(this.lib.symbols.getKeymapEntryCount(settings, scope, mode));
            if (count === 0) return [];

            const entrySize = KeymapEntry.size;
            const buf = new ArrayBuffer(count * entrySize);
            const actual = Number(
                this.lib.symbols.readKeymapEntries(settings, scope, mode, ptr(buf), count),
            );

            const entries: Array<{ sequence: string; action: string }> = [];
            for (let i = 0; i < actual; i++) {
                const slice = buf.slice(i * entrySize, (i + 1) * entrySize);
                const { sequence, action } = KeymapEntry.unpack(slice);
                if (sequence && action) {
                    entries.push({ sequence, action });
                }
            }
            return entries;
        } finally {
            this.lib.symbols.unlockSettings(settings);
        }
    }

    openBuffer(project: Pointer, entryId: number): Pointer | null {
        return this.lib.symbols.openBuffer(project, entryId) as Pointer | null;
    }

    closeBuffer(project: Pointer, entryId: number): void {
        this.lib.symbols.closeBuffer(project, entryId);
    }

    readBuffer(buffer: Pointer): ReturnType<typeof BufferData.unpack> {
        const buf = new ArrayBuffer(BufferData.size);
        this.lib.symbols.readBuffer(buffer, ptr(buf));
        return BufferData.unpack(buf);
    }

    setSystemScheme(settings: Pointer, scheme: number): void {
        this.lib.symbols.setSystemScheme(settings, scheme);
    }

    drainMailbox() {
        this.lib.symbols.drainMailbox();
    }

    gpuInit(metalLayerPtr: Pointer): Pointer | null {
        return this.lib.symbols.gpuInit(metalLayerPtr) as Pointer | null;
    }

    gpuStartRenderLoop(ctx: Pointer): void {
        this.lib.symbols.gpuStartRenderLoop(ctx);
    }

    gpuResize(ctx: Pointer, width: number, height: number): void {
        this.lib.symbols.gpuResize(ctx, width, height);
    }

    gpuDestroy(ctx: Pointer): void {
        this.lib.symbols.gpuDestroy(ctx);
    }

}

let coreLib: CoreLib | undefined

export function resolveCoreLib(libPath?: string): CoreLib {
    if (!coreLib) {
        try {
            coreLib = new CoreLib(libPath)
        } catch (error) {
            throw new Error(
                `Failed to initialize the core lib, path`
            )
        }
    }
    return coreLib
}

