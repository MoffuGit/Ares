import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { App, CoreLib } from "@ares/core";
import type { Surface, SurfaceKind } from "@ares/shared";

type Rect = { x: number; y: number; width: number; height: number };

type SurfaceState = {
    id: number;
    surface: Surface;
    rect: Rect;
    corePtr: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class SurfaceStore {
    private states = new Map<number, SurfaceState>();
    app: App;

    constructor(app: App) {
        this.app = app;
    }

    start(surfaceId: number, _win: unknown, rect: Rect, surface: Surface) {
        console.log("view", surfaceId, "request to start");
        if (this.states.has(surfaceId)) return;

        const wgpuView = WGPUView.getById(surfaceId);
        if (!wgpuView?.ptr) {
            throw new Error(`GPU view not found for id ${surfaceId}`);
        }

        const metalLayerPtr = wgpuView.getNativeHandle();
        if (!metalLayerPtr) {
            throw new Error(`Failed to get Metal layer pointer for view ${surfaceId}`);
        }

        if (!this.app.coreProject) throw new Error(`There is no project for this surface ${surfaceId}`);
        const corePtr = this.createCoreSurface(surface.kind, metalLayerPtr);
        if (!corePtr) {
            throw new Error(`Failed to create view (kind=${surface.kind}) for id ${surfaceId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        console.log("view", surfaceId, "started");

        this.resizeCoreSurface(this.app.core, surface.kind, corePtr, width, height);

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

    private createCoreSurface(kind: SurfaceKind, metalLayerPtr: Pointer): Pointer | null {
        switch (kind) {
            case "editor":
                return this.app.coreProject ? this.app.core.createEditor(this.app.coreApp, this.app.coreProject, metalLayerPtr) : null;
            case "terminal":
                return this.app.core.createTerminal(this.app.coreApp, metalLayerPtr);
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
