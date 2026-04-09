import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { App, CoreLib } from "@ares/core";
import type { EditorState, Surface, SurfaceKind, SurfaceState } from "@ares/shared";

type Rect = { x: number; y: number; width: number; height: number };

type SurfaceRecord = {
    id: number;
    surface: Surface;
    rect: Rect;
    corePtr: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class SurfaceStore {
    private states = new Map<number, SurfaceRecord>();
    app: App;

    constructor(app: App) {
        this.app = app;
    }

    start(surfaceId: number, _win: unknown, rect: Rect, surface: Surface) {
        console.log("view", surfaceId, "request to start");
        if (this.states.has(surfaceId)) return;

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        const wgpuView = WGPUView.getById(surfaceId);
        if (!wgpuView?.ptr) {
            throw new Error(`GPU view not found for id ${surfaceId}`);
        }

        const metalLayerPtr = wgpuView.getNativeHandle();
        if (!metalLayerPtr) {
            throw new Error(`Failed to get Metal layer pointer for view ${surfaceId}`);
        }

        if (!this.app.coreProject) throw new Error(`There is no project for this surface ${surfaceId}`);
        const corePtr = this.createCoreSurface(surface.kind, metalLayerPtr, width, height);
        if (!corePtr) {
            throw new Error(`Failed to create view (kind=${surface.kind}) for id ${surfaceId}`);
        }

        console.log("view", surfaceId, "started");

        this.states.set(surfaceId, {
            id: surfaceId,
            surface,
            rect,
            corePtr,
            lastWidth: width,
            lastHeight: height,
        });
    }

    updateRect(viewId: number, rect: Rect) {
        const state = this.states.get(viewId);
        if (!state) return;

        state.rect = rect;
        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        if (width !== state.lastWidth || height !== state.lastHeight) {
            this.resizeCoreSurface(this.app.core, state.surface.kind, state.corePtr, width, height);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(viewId: number) {
        console.log("view", viewId, "stopped");
        const state = this.states.get(viewId);
        if (!state) return;

        this.destroyCoreSurface(this.app.core, state.surface.kind, state.corePtr);
        this.states.delete(viewId);
    }

    stopAll() {
        for (const viewId of this.states.keys()) {
            this.stop(viewId);
        }
    }

    setVisibility(viewId: number, visible: boolean) {
        const state = this.states.get(viewId);
        if (!state) return;

        switch (state.surface.kind) {
            case "editor":
                this.app.core.setEditorVisibility(state.corePtr, visible);
                break;
            case "terminal":
                break;
        }
    }

    selectSurfaceEntry(viewId: number, id: number) {
        const state = this.states.get(viewId);
        if (!state || state.surface.kind !== "editor") return;
        this.app.core.selectEditorEntry(state.corePtr, id);
    }

    surfaceScrollTo(viewId: number, row: number) {
        const state = this.states.get(viewId);
        if (!state || state.surface.kind !== "editor") return;
        this.app.core.editorScrollTo(state.corePtr, row);
    }

    surfaceMouseEvent(viewId: number, type: "mousedown" | "mousemove" | "mouseup", x: number, y: number, button: number) {
        const state = this.states.get(viewId);
        if (!state) return;
        console.log(`[SurfaceStore] mouse ${type} on surface ${viewId}: (${x}, ${y}) button=${button}`);
    }

    readSurfaceState(viewId: number): SurfaceState | null {
        const state = this.states.get(viewId);
        if (!state) return null;

        switch (state.surface.kind) {
            case "editor":
                return this.app.core.readEditorSurfaceState(state.corePtr);
            case "terminal":
                return this.app.core.readTerminalSurfaceState(state.corePtr);
        }
    }

    readEditorState(viewId: number): EditorState | null {
        const state = this.states.get(viewId);
        if (!state || state.surface.kind !== "editor") return null;
        return this.app.core.readEditorState(state.corePtr);
    }

    readAllSurfaceStates(): Array<{ surfaceId: number; state: SurfaceState }> {
        const updates: Array<{ surfaceId: number; state: SurfaceState }> = [];
        for (const state of this.states.values()) {
            const surfaceState = this.readSurfaceState(state.id);
            if (surfaceState) {
                updates.push({ surfaceId: state.id, state: surfaceState });
            }
        }
        return updates;
    }

    readAllEditorStates(): Array<{ surfaceId: number; state: EditorState | null }> {
        const updates: Array<{ surfaceId: number; state: EditorState | null }> = [];
        for (const state of this.states.values()) {
            if (state.surface.kind !== "editor") continue;
            updates.push({ surfaceId: state.id, state: this.readEditorState(state.id) });
        }
        return updates;
    }

    private createCoreSurface(kind: SurfaceKind, metalLayerPtr: Pointer, width: number, height: number): Pointer | null {
        switch (kind) {
            case "editor":
                return this.app.coreProject ? this.app.core.createEditor(this.app.coreApp, this.app.coreProject, metalLayerPtr, width, height) : null;
            case "terminal":
                return this.app.core.createTerminal(this.app.coreApp, metalLayerPtr, width, height);
        }
    }

    private resizeCoreSurface(core: CoreLib, kind: SurfaceKind, ptr: Pointer, width: number, height: number) {
        switch (kind) {
            case "editor":
                core.resizeEditor(ptr, width, height);
                break;
            case "terminal":
                break;
        }
    }

    private destroyCoreSurface(core: CoreLib, kind: SurfaceKind, ptr: Pointer) {
        switch (kind) {
            case "editor":
                core.destroyEditor(ptr);
                break;
            case "terminal":
                core.destroyTerminal(ptr);
                break;
        }
    }
}
