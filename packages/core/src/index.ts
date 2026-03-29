import { dlopen, FFIType, JSCallback, ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { EventEmitter } from "events";
import { resolve } from "path";
import { EventType, Events, EventsName } from "./events";
import { BufferState, KeymapEntry, Settings, WorktreeEntry } from "./structs";

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
            createApp: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyApp: {
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
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
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
            createProject: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64],
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
            setSystemScheme: {
                args: [FFIType.pointer, FFIType.u8],
                returns: FFIType.void,
            },
            drainMailbox: {
                args: [],
                return: FFIType.void,
            },
            createEditor: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.pointer,
            },
            resizeEditor: {
                args: [FFIType.pointer, FFIType.u32, FFIType.u32],
                returns: FFIType.void,
            },
            selectEditorEntry: {
                args: [FFIType.pointer, FFIType.u64],
                returns: FFIType.void
            },
            editorScrollTo: {
                args: [FFIType.pointer, FFIType.u64],
                returns: FFIType.void
            },
            readBufferState: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.bool,
            },
            setEditorVisibility: {
                args: [FFIType.pointer, FFIType.bool],
                returns: FFIType.void
            },
            destroyEditor: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
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
                        console.log("event with data received", event, data);
                        this.emit(event, data);
                    })

                }
            },
            {
                args: [FFIType.u8, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
                // These mailbox events are delivered only while JS is actively calling
                // `drainMailbox()`, so the payload pointer is only borrowed for the
                // duration of this native call. Keep the callback synchronous so we
                // unpack the data before Zig stack memory can be reused.
                threadsafe: false,
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

    createApp(): Pointer | null {
        return this.lib.symbols.createApp();
    }

    destroyApp(app: Pointer) {
        this.lib.symbols.destroyApp(app);
    }

    setWindowTrafficLightsPosition(window: Pointer, x: number, y: number) {
        this.lib.symbols.setWindowTrafficLightsPosition(window, x, y);
    }

    loadSettings(app: Pointer, path: string): void {
        const buf = new TextEncoder().encode(path);
        this.lib.symbols.loadSettings(app, buf, buf.byteLength);
    }

    readSettings(app: Pointer) {
        this.lib.symbols.lockSettings(app);
        try {
            const buf = new ArrayBuffer(Settings.size);
            this.lib.symbols.readSettings(app, ptr(buf));
            return Settings.unpack(buf);
        } finally {
            this.lib.symbols.unlockSettings(app);
        }
    }

    readThemeJson(app: Pointer): string {
        this.lib.symbols.lockSettings(app);
        try {
            const len = Number(this.lib.symbols.getThemeJsonLen(app));
            if (len === 0) return "{}";
            const buf = new ArrayBuffer(len);
            this.lib.symbols.readThemeJson(app, ptr(buf), len);
            return new TextDecoder().decode(buf);
        } finally {
            this.lib.symbols.unlockSettings(app);
        }
    }

    createProject(app: Pointer, path: string): Pointer | null {
        const buf = new TextEncoder().encode(path);
        return this.lib.symbols.createProject(app, buf, buf.byteLength) as Pointer | null;
    }

    destroyProject(handle: Pointer): void {
        this.lib.symbols.destroyProject(handle);
    }

    readFileTree(project: Pointer) {
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
        return entries;
    }

    expandEntry(project: Pointer, id: number): void {
        this.lib.symbols.expandEntry(project, id);
    }

    getTrieRoot(app: Pointer, mode: number): Pointer | null {
        return this.lib.symbols.getTrieRoot(app, mode) as Pointer | null;
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

    readKeymapEntries(app: Pointer, scope: number, mode: number): Array<{ sequence: string; action: string }> {
        this.lib.symbols.lockSettings(app);
        try {
            const count = Number(this.lib.symbols.getKeymapEntryCount(app, scope, mode));
            if (count === 0) return [];

            const entrySize = KeymapEntry.size;
            const buf = new ArrayBuffer(count * entrySize);
            const actual = Number(
                this.lib.symbols.readKeymapEntries(app, scope, mode, ptr(buf), count),
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
            this.lib.symbols.unlockSettings(app);
        }
    }

    setSystemScheme(app: Pointer, scheme: number): void {
        this.lib.symbols.setSystemScheme(app, scheme);
    }

    drainMailbox() {
        this.lib.symbols.drainMailbox();
    }

    createEditor(project: Pointer, metalLayerPtr: Pointer): Pointer | null {
        return this.lib.symbols.createEditor(project, metalLayerPtr) as Pointer | null;
    }

    resizeEditor(editor: Pointer, width: number, height: number): void {
        this.lib.symbols.resizeEditor(editor, width, height);
    }

    selectEditorEntry(editor: Pointer, id: number) {
        this.lib.symbols.selectEditorEntry(editor, id);
    }

    editorScrollTo(editor: Pointer, row: number) {
        this.lib.symbols.editorScrollTo(editor, row);
    }

    readBufferState(editor: Pointer): { entry_id: number; row_count: number; cell_width: number; cell_height: number; renderer_health: number } | null {
        const buf = new ArrayBuffer(BufferState.size);
        const ok = this.lib.symbols.readBufferState(editor, ptr(buf));
        if (!ok) return null;
        const raw = BufferState.unpack(buf);
        return { entry_id: Number(raw.entry_id), row_count: Number(raw.row_count), cell_width: Number(raw.cell_width), cell_height: Number(raw.cell_height), renderer_health: Number(raw.renderer_health) };
    }

    setEditorVisibility(editor: Pointer, visible: boolean) {
        this.lib.symbols.setEditorVisibility(editor, visible);
    }

    destroyEditor(editor: Pointer): void {
        this.lib.symbols.destroyEditor(editor);
    }

}

let coreLib: CoreLib | undefined

export function resolveCoreLib(libPath?: string): CoreLib {
    if (!coreLib) {
        const resolvedPath = libPath ?? DEFAULT_LIB_PATH;
        coreLib = new CoreLib(resolvedPath);
    }
    return coreLib
}
