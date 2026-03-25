import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { Surface, SurfaceKind } from "@ares/shared";
import { App } from "node_modules/@ares/shared/src/app";

type Rect = { x: number; y: number; width: number; height: number };

const SurfaceKindMap: Record<SurfaceKind, number> = {
    editor: 0,
    terminal: 1,
};

type SurfaceState = {
    viewId: number;
    view: Surface;
    rect: Rect;
    coreSurface: Pointer;
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

        const coreSurface = app.createSurface(SurfaceKindMap[view.kind], metalLayerPtr);
        if (!coreSurface) {
            throw new Error(`Failed to create view (kind=${view.kind}) for id ${viewId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        console.log("view", viewId, "started");

        app.resizeSurface(coreSurface, width, height);

        this.states.set(viewId, {
            viewId,
            view,
            rect,
            coreSurface: coreSurface,
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
            app.resizeSurface(state.coreSurface, width, height);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(app: App, viewId: number) {
        console.log("view", viewId, "stopped");
        const state = this.states.get(viewId);
        if (!state) return;

        app.destroySurface(state.coreSurface);
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
        app.setSurfaceVisibility(state.coreSurface, visible);
    }

    selectSurfaceEntry(app: App, viewId: number, id: number) {
        const state = this.states.get(viewId);
        if (!state || state.view.kind != "editor") return;
        app.selectSurfaceEntry(state.coreSurface, id);
    }

    surfaceScrollTo(app: App, viewId: number, row: number) {
        const state = this.states.get(viewId);
        if (!state || state.view.kind != "editor") return;
        app.surfaceScrollTo(state.coreSurface, row);
    }
}
