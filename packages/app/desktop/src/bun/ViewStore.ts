import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { View, ViewKind } from "@ares/shared";
import { App } from "node_modules/@ares/shared/src/app";

type Rect = { x: number; y: number; width: number; height: number };

const ViewKindMap: Record<ViewKind, number> = {
    editor: 0,
    terminal: 1,
};

type ViewState = {
    viewId: number;
    view: View;
    rect: Rect;
    coreView: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class ViewStore {
    private states = new Map<number, ViewState>();


    start(app: App, viewId: number, _win: unknown, rect: Rect, view: View) {
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

        const coreView = app.createView(ViewKindMap[view.kind], metalLayerPtr);
        if (!coreView) {
            throw new Error(`Failed to create view (kind=${view.kind}) for id ${viewId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        console.log("view", viewId, "started");

        app.resizeView(coreView, width, height);

        this.states.set(viewId, {
            viewId,
            view,
            rect,
            coreView: coreView,
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
            app.resizeView(state.coreView, width, height);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(app: App, viewId: number) {
        console.log("view", viewId, "stopped");
        const state = this.states.get(viewId);
        if (!state) return;

        app.destroyView(state.coreView);
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
        app.setViewVisibility(state.coreView, visible);
    }

    selectEntry(app: App, viewId: number, id: number) {
        const state = this.states.get(viewId);
        if (!state || state.view.kind != "editor") return;
        app.selectEntry(state.coreView, id);
    }
}
