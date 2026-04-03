import { rpc, useAppStore } from "@/lib/app";
import type { Surface } from "@ares/shared";
import useResizeObserver from "@react-hook/resize-observer";
import { useCallback, useEffect, useRef, type RefObject } from "react";
import type { GpuTagHandle } from "../gpu-tag";

type RectLike = Pick<DOMRectReadOnly, "x" | "y" | "width" | "height">;

type UseGpuSurfaceOptions<TSurface extends Surface> = {
    id: number;
    surface: TSurface;
    active: boolean;
    containerRef: RefObject<HTMLElement | null>;
    onReadySuccess?: (gpuSurfaceId: number) => void | Promise<void>;
};

function toGpuRect(rect: RectLike) {
    return {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    };
}

export function useGpuSurface<TSurface extends Surface>({
    id,
    surface,
    active,
    containerRef,
    onReadySuccess,
}: UseGpuSurfaceOptions<TSurface>) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuSurfaceId: number) => {
        useAppStore.getState().setGpuSurfaceId(id, gpuSurfaceId);

        const rectElement = containerRef.current ?? gpuRef.current?.element;
        if (!rectElement) return;

        try {
            const res = await rpc.request.gpuTagReady({
                id: gpuSurfaceId,
                rect: toGpuRect(rectElement.getBoundingClientRect()),
                surface,
            });

            if (res.success) {
                await onReadySuccess?.(gpuSurfaceId);
            }
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [containerRef, id, onReadySuccess, surface]);

    useEffect(() => {
        gpuRef.current?.toggleHidden(!active);

        if (surface.gpuSurfaceId != null) {
            rpc.send("gpuTagVisibility", { id: surface.gpuSurfaceId, visible: active });
        }
    }, [active, surface.gpuSurfaceId]);

    useResizeObserver(containerRef, (entry) => {
        if (!surface.gpuSurfaceId) return;

        rpc.send("gpuTagRect", {
            id: surface.gpuSurfaceId,
            rect: toGpuRect(entry.contentRect),
        });
    });

    return { gpuRef, handleReady };
}
