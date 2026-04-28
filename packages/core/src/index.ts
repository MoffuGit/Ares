import { dlopen, FFIType, JSCallback, ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { EventEmitter } from "events";
import { resolve } from "path";
import { EventType, Events, EventsName } from "./events";
import {
    EditorState as RawEditorState,
    KeymapMatch as RawKeymapMatch,
    Settings as RawSettings,
    SurfaceState as RawSurfaceState,
    WorktreeEntry as RawWorktreeEntry,
} from "./structs";
import { resolveTheme } from "./theme";
import type {
    EditorState,
    KeymapMatch,
    Mode,
    Settings,
    SurfaceState,
    Theme,
    WorktreeEntry,
} from "@ares/shared";

const DEFAULT_LIB_PATH = resolve(import.meta.dir, "../../../zig-out/lib/libcore.dylib");

function toNumber(value: number | bigint): number {
    return typeof value === "bigint" ? Number(value) : value;
}

function mapSurfaceState(raw: {
    surface_id?: number | bigint;
    cell_width: number | bigint;
    cell_height: number | bigint;
    renderer_health: number | bigint;
}): SurfaceState {
    return {
        cellWidth: toNumber(raw.cell_width),
        cellHeight: toNumber(raw.cell_height),
        rendererHealth: toNumber(raw.renderer_health),
    };
}

function mapEditorState(raw: {
    surface_id?: number | bigint;
    entry_id: number | bigint;
    row_count: number | bigint;
    scroll_row: number | bigint;
    cursor_row: number | bigint;
    cursor_col: number | bigint;
}): EditorState {
    return {
        entryId: toNumber(raw.entry_id),
        rowCount: toNumber(raw.row_count),
        scrollRow: toNumber(raw.scroll_row),
        cursorRow: toNumber(raw.cursor_row),
        cursorCol: toNumber(raw.cursor_col),
    };
}

function mapSurfaceUpdate(raw: {
    surface_id: number | bigint;
    cell_width: number | bigint;
    cell_height: number | bigint;
    renderer_health: number | bigint;
}): { surfaceId: number; state: SurfaceState } {
    return {
        surfaceId: toNumber(raw.surface_id),
        state: mapSurfaceState(raw),
    };
}

function mapEditorUpdate(raw: {
    surface_id: number | bigint;
    entry_id: number | bigint;
    row_count: number | bigint;
    scroll_row: number | bigint;
    cursor_row: number | bigint;
    cursor_col: number | bigint;
}): { surfaceId: number; state: EditorState } {
    return {
        surfaceId: toNumber(raw.surface_id),
        state: mapEditorState(raw),
    };
}

function mapWorktreeEntry(raw: ReturnType<typeof RawWorktreeEntry.unpack>): WorktreeEntry {
    const path = raw.path ?? "";
    const parts = path.split("/");

    return {
        id: toNumber(raw.id),
        name: parts[parts.length - 1] ?? path,
        path,
        kind: raw.kind === 1 ? "dir" : "file",
        fileType: raw.file_type ?? "unknown",
        expanded: raw.is_expanded,
        depth: raw.depth,
    };
}

function mapMode(value: number | bigint): Mode {
    switch (toNumber(value)) {
        case 1:
            return "insert";
        case 2:
            return "visual";
        default:
            return "normal";
    }
}

function mapKeymapMatch(raw: ReturnType<typeof RawKeymapMatch.unpack>): KeymapMatch {
    return {
        sequence: raw.sequence ?? "",
        action: raw.action ?? "",
    };
}

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
                args: [FFIType.pointer],
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
            setSystemScheme: {
                args: [FFIType.pointer, FFIType.u8],
                returns: FFIType.void,
            },
            drainMailbox: {
                args: [],
                return: FFIType.void,
            },
            createEditor: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64, FFIType.pointer, FFIType.u32, FFIType.u32],
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
            editorSetCursorPosition: {
                args: [FFIType.pointer, FFIType.u64, FFIType.u64],
                returns: FFIType.void,
            },
            editorSurfaceMouseButton: {
                args: [FFIType.pointer, FFIType.u8, FFIType.u8, FFIType.f64, FFIType.f64, FFIType.u8],
                returns: FFIType.void,
            },
            editorSurfaceMouseMove: {
                args: [FFIType.pointer, FFIType.f64, FFIType.f64, FFIType.u8],
                returns: FFIType.void,
            },
            editorSurfaceKeyEvent: {
                args: [FFIType.pointer, FFIType.pointer, FFIType.u64, FFIType.u8, FFIType.bool],
                returns: FFIType.void,
            },
            readEditorSurfaceState: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.void,
            },
            readTerminalSurfaceState: {
                args: [FFIType.pointer, FFIType.pointer],
                returns: FFIType.void,
            },
            readEditorState: {
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
            createTerminal: {
                args: [FFIType.pointer, FFIType.u64, FFIType.pointer, FFIType.u32, FFIType.u32],
                returns: FFIType.pointer,
            },
            destroyTerminal: {
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
                    const rawData = dataType.unpack(toArrayBuffer(ptr, 0, _len));
                    const data = _type === EventType.SurfaceUpdate
                        ? mapSurfaceUpdate(rawData)
                        : _type === EventType.EditorUpdate
                            ? mapEditorUpdate(rawData)
                            : _type === EventType.ModeUpdate
                                ? { mode: mapMode(rawData.mode) }
                                : _type === EventType.KeymapMatch
                                    ? mapKeymapMatch(rawData)
                                    : rawData;
                    const event = EventsName[_type];
                    queueMicrotask(() => {
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

    createApp(window: Pointer): Pointer | null {
        return this.lib.symbols.createApp(window);
    }

    destroyApp(app: Pointer) {
        this.lib.symbols.destroyApp(app);
    }

    loadSettings(app: Pointer, path: string): void {
        const buf = new TextEncoder().encode(path);
        this.lib.symbols.loadSettings(app, buf, buf.byteLength);
    }

    readSettings(app: Pointer) {
        this.lib.symbols.lockSettings(app);
        try {
            const buf = new ArrayBuffer(RawSettings.size);
            this.lib.symbols.readSettings(app, ptr(buf));
            const raw = RawSettings.unpack(buf);
            return {
                scheme: raw.scheme,
                system_scheme: raw.system_scheme,
                tabs_position: raw.tabs_position,
                light_theme: raw.light_theme ?? "",
                dark_theme: raw.dark_theme ?? "",
            } satisfies Settings;
        } finally {
            this.lib.symbols.unlockSettings(app);
        }
    }

    readTheme(app: Pointer): Theme {
        this.lib.symbols.lockSettings(app);
        try {
            const len = Number(this.lib.symbols.getThemeJsonLen(app));
            if (len === 0) return resolveTheme("{}");
            const buf = new ArrayBuffer(len);
            this.lib.symbols.readThemeJson(app, ptr(buf), len);
            return resolveTheme(new TextDecoder().decode(buf));
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

    readFileTree(project: Pointer): WorktreeEntry[] {
        const count = Number(this.lib.symbols.getFiletreeCount(project));
        if (count === 0) return [];

        const entrySize = RawWorktreeEntry.size;
        const buf = new ArrayBuffer(count * entrySize);
        const actual = Number(this.lib.symbols.readFiletree(project, ptr(buf), count));

        const entries: WorktreeEntry[] = [];
        for (let i = 0; i < actual; i++) {
            const slice = buf.slice(i * entrySize, (i + 1) * entrySize);
            entries.push(mapWorktreeEntry(RawWorktreeEntry.unpack(slice)));
        }
        return entries;
    }

    expandEntry(project: Pointer, id: number): void {
        this.lib.symbols.expandEntry(project, id);
    }

    setSystemScheme(app: Pointer, scheme: number): void {
        this.lib.symbols.setSystemScheme(app, scheme);
    }

    drainMailbox() {
        this.lib.symbols.drainMailbox();
    }

    createEditor(app: Pointer, project: Pointer, surfaceId: number, metalLayerPtr: Pointer, width: number, height: number): Pointer | null {
        return this.lib.symbols.createEditor(app, project, surfaceId, metalLayerPtr, width, height) as Pointer | null;
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

    editorSetCursorPosition(editor: Pointer, row: number, col: number) {
        this.lib.symbols.editorSetCursorPosition(editor, row, col);
    }

    editorSurfaceMouseButton(surface: Pointer, button: number, action: number, x: number, y: number, mods: number) {
        this.lib.symbols.editorSurfaceMouseButton(surface, button, action, x, y, mods);
    }

    editorSurfaceMouseMove(surface: Pointer, x: number, y: number, mods: number) {
        this.lib.symbols.editorSurfaceMouseMove(surface, x, y, mods);
    }

    editorSurfaceKeyEvent(surface: Pointer, key: string, mods: number, repeat: boolean) {
        const buf = new TextEncoder().encode(key);
        this.lib.symbols.editorSurfaceKeyEvent(surface, buf, buf.byteLength, mods, repeat);
    }

    readEditorSurfaceState(editor: Pointer): SurfaceState {
        const buf = new ArrayBuffer(RawSurfaceState.size);
        this.lib.symbols.readEditorSurfaceState(editor, ptr(buf));
        return mapSurfaceState(RawSurfaceState.unpack(buf));
    }

    readTerminalSurfaceState(terminal: Pointer): SurfaceState {
        const buf = new ArrayBuffer(RawSurfaceState.size);
        this.lib.symbols.readTerminalSurfaceState(terminal, ptr(buf));
        return mapSurfaceState(RawSurfaceState.unpack(buf));
    }

    readEditorState(editor: Pointer): EditorState | null {
        const buf = new ArrayBuffer(RawEditorState.size);
        const ok = this.lib.symbols.readEditorState(editor, ptr(buf));
        if (!ok) return null;
        return mapEditorState(RawEditorState.unpack(buf));
    }

    setEditorVisibility(editor: Pointer, visible: boolean) {
        this.lib.symbols.setEditorVisibility(editor, visible);
    }

    destroyEditor(editor: Pointer): void {
        this.lib.symbols.destroyEditor(editor);
    }

    createTerminal(app: Pointer, surfaceId: number, layer: Pointer, width: number, height: number): Pointer | null {
        return this.lib.symbols.createTerminal(app, surfaceId, layer, width, height);
    }

    destroyTerminal(terminal: Pointer) {
        this.lib.symbols.destroyTerminal(terminal);
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

export * from "./app.ts";
