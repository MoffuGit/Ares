import { WGPUView } from "electrobun/bun";
import type { Pointer } from "bun:ffi";
import type { CoreLib } from "@ares/core";

type Rect = { x: number; y: number; width: number; height: number };

type ViewState = {
    viewId: number;
    rect: Rect;
    gpuCtx: Pointer;
    lastWidth: number;
    lastHeight: number;
};

export class MetalRenderer {
    private core: CoreLib;
    private states = new Map<number, ViewState>();

    constructor(core: CoreLib) {
        this.core = core;
    }

    start(viewId: number, _win: unknown, rect: Rect) {
        if (this.states.has(viewId)) return;

        const view = WGPUView.getById(viewId);
        if (!view?.ptr) {
            throw new Error(`WGPUView not found for id ${viewId}`);
        }

        const metalLayerPtr = view.getNativeHandle();
        if (!metalLayerPtr) {
            throw new Error(`Failed to get Metal layer pointer for view ${viewId}`);
        }

        const gpuCtx = this.core.gpuInit(metalLayerPtr);
        if (!gpuCtx) {
            throw new Error(`Failed to initialize Metal GPU context for view ${viewId}`);
        }

        const width = Math.max(1, Math.floor(rect.width));
        const height = Math.max(1, Math.floor(rect.height));

        this.core.gpuResize(gpuCtx, width * 2, height * 2);
        this.core.gpuStartRenderLoop(gpuCtx);

        this.states.set(viewId, {
            viewId,
            rect,
            gpuCtx,
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
            this.core.gpuResize(state.gpuCtx, width * 2, height * 2);
            state.lastWidth = width;
            state.lastHeight = height;
        }
    }

    stop(viewId: number) {
        const state = this.states.get(viewId);
        if (!state) return;

        this.core.gpuDestroy(state.gpuCtx);
        this.states.delete(viewId);
    }

    stopAll() {
        for (const viewId of this.states.keys()) {
            this.stop(viewId);
        }
    }
}
