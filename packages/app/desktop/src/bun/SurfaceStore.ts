import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { Surface, SurfaceKind } from "@ares/shared";
import { App } from "node_modules/@ares/shared/src/app";

type Rect = { x: number; y: number; width: number; height: number };

type SurfaceState = {
    viewId: number;
    view: Surface;
    rect: Rect;
    corePtr: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class SurfaceStore {
    private states = new Map<number, SurfaceState>();

    start(app: App, viewId: number, _win: unknown, rect: Rect, view: Surface) {
        console.log("view", viewId, "request to start");
        if (this.states.has(viewId)) return;

        const wgpuView = WGPUView.getById(viewId);
        if (!wgpuView?.ptr) {
            throw new Error(`GPU view not found for id ${viewId}`);
        }

        const metalLayerPtr = wgpuView.getNativeHandle();
        if (!metalLayerPtr) {
            throw new Error(`Failed to get Metal layer pointer for view ${viewId}`);
        }

        const corePtr = this.createCoreSurface(app, view.kind, metalLayerPtr);
        if (!corePtr) {
            throw new Error(`Failed to create view (kind=${view.kind}) for id ${viewId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        console.log("view", viewId, "started");

        this.resizeCoreSurface(app, view.kind, corePtr, width, height);

        this.states.set(viewId, {
            viewId,
            view,
            rect,
            corePtr,
            lastWidth: width,
            lastHeight: height,
        });
    }

    updateRect(app: App, viewId: number, rect: Rect) {
        const state = this.states.get(viewId);
        if (!state) return;

        state.rect = rect;
        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        if (width !== state.lastWidth || height !== state.lastHeight) {
            this.resizeCoreSurface(app, state.view.kind, state.corePtr, width, height);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(app: App, viewId: number) {
        console.log("view", viewId, "stopped");
        const state = this.states.get(viewId);
        if (!state) return;

        this.destroyCoreSurface(app, state.view.kind, state.corePtr);
        this.states.delete(viewId);
    }

    stopAll(app: App) {
        for (const viewId of this.states.keys()) {
            this.stop(app, viewId);
        }
    }

    setVisibility(app: App, viewId: number, visible: boolean) {
        const state = this.states.get(viewId);
        if (!state) return;

        switch (state.view.kind) {
            case "editor":
                app.setEditorVisibility(state.corePtr, visible);
                break;
            case "terminal":
                break;
        }
    }

    selectSurfaceEntry(app: App, viewId: number, id: number) {
        const state = this.states.get(viewId);
        if (!state || state.view.kind !== "editor") return;
        app.selectEditorEntry(state.corePtr, id);
    }

    surfaceScrollTo(app: App, viewId: number, row: number) {
        const state = this.states.get(viewId);
        if (!state || state.view.kind !== "editor") return;
        app.editorScrollTo(state.corePtr, row);
    }

    private createCoreSurface(app: App, kind: SurfaceKind, metalLayerPtr: Pointer): Pointer | null {
        switch (kind) {
            case "editor":
                return app.createEditor(metalLayerPtr);
            case "terminal":
                return null;
        }
    }

    private resizeCoreSurface(app: App, kind: SurfaceKind, ptr: Pointer, width: number, height: number) {
        switch (kind) {
            case "editor":
                app.resizeEditor(ptr, width, height);
                break;
            case "terminal":
                break;
        }
    }

    private destroyCoreSurface(app: App, kind: SurfaceKind, ptr: Pointer) {
        switch (kind) {
            case "editor":
                app.destroyEditor(ptr);
                break;
            case "terminal":
                break;
        }
    }
}
