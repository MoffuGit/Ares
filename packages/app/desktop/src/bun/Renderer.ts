import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { CoreLib } from "@ares/core";
import type { View, ViewKind } from "@ares/shared";

type Rect = { x: number; y: number; width: number; height: number };

const ViewKindMap: Record<ViewKind, number> = {
    editor: 0,
    terminal: 1,
};

type ViewState = {
    viewId: number;
    view: View;
    rect: Rect;
    gpuView: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class Renderer {
    private core: CoreLib;
    private states = new Map<number, ViewState>();

    constructor(core: CoreLib) {
        this.core = core;
    }

    start(viewId: number, _win: unknown, rect: Rect, view: View) {
        if (this.states.has(viewId)) return;

        const wgpuView = WGPUView.getById(viewId);
        if (!wgpuView?.ptr) {
            throw new Error(`GPU view not found for id ${viewId}`);
        }

        const metalLayerPtr = wgpuView.getNativeHandle();
        if (!metalLayerPtr) {
            throw new Error(`Failed to get Metal layer pointer for view ${viewId}`);
        }

        const gpuView = this.core.createView(ViewKindMap[view.kind], metalLayerPtr);
        if (!gpuView) {
            throw new Error(`Failed to create view (kind=${view.kind}) for id ${viewId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        this.core.resizeView(gpuView, width * 2, height * 2);

        this.states.set(viewId, {
            viewId,
            view,
            rect,
            gpuView,
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
            this.core.resizeView(state.gpuView, width * 2, height * 2);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(viewId: number) {
        const state = this.states.get(viewId);
        if (!state) return;

        this.core.destroyView(state.gpuView);
        this.states.delete(viewId);
    }

    stopAll() {
        for (const viewId of this.states.keys()) {
            this.stop(viewId);
        }
    }
}
